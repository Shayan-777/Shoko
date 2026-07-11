/* shoko-translate: offline translation engine for Shoko.
 *
 * Speaks JSON-lines over stdin/stdout. One request per line, one response
 * per line. Requests carry only flat string fields:
 *   {"op":"ping"}
 *   {"op":"load","slot":"eten","model":"/path.bin","vocab":"/path.spm"}
 *   {"op":"translate","slot":"eten","text":"Tere!"}
 *   {"op":"unload","slot":"eten"}
 * Responses: {"ok":true,...} or {"ok":false,"error":"..."}.
 */
#define _POSIX_C_SOURCE 200809L

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "marian_bin.h"
#include "nn.h"
#include "spm.h"

#define SK_ENGINE_VERSION "1.0.0"
#define SK_MAX_SLOTS 4
#define SK_MAX_LINE (1 << 20)

typedef struct {
  char name[64];
  sk_nn *model;
  unsigned long last_used;
} sk_slot;

static sk_slot slots[SK_MAX_SLOTS];
static unsigned long use_counter;

/* --- JSON ---------------------------------------------------------------- */

/* Extracts a string value for "key" from a flat JSON object. Handles the
 * standard escapes including \uXXXX with surrogate pairs. Returns a malloc'd
 * string or NULL when the key is absent/malformed. */
static char *json_get_string(const char *line, const char *key) {
  char pattern[80];
  snprintf(pattern, sizeof(pattern), "\"%s\"", key);
  const char *p = strstr(line, pattern);
  if (!p) return NULL;
  p += strlen(pattern);
  while (*p == ' ' || *p == '\t') p++;
  if (*p != ':') return NULL;
  p++;
  while (*p == ' ' || *p == '\t') p++;
  if (*p != '"') return NULL;
  p++;

  size_t cap = strlen(p) + 1;
  char *out = malloc(cap);
  if (!out) return NULL;
  size_t n = 0;
  while (*p && *p != '"') {
    if (*p == '\\') {
      p++;
      switch (*p) {
      case '"': out[n++] = '"'; p++; break;
      case '\\': out[n++] = '\\'; p++; break;
      case '/': out[n++] = '/'; p++; break;
      case 'b': out[n++] = '\b'; p++; break;
      case 'f': out[n++] = '\f'; p++; break;
      case 'n': out[n++] = '\n'; p++; break;
      case 'r': out[n++] = '\r'; p++; break;
      case 't': out[n++] = '\t'; p++; break;
      case 'u': {
        unsigned cp;
        if (sscanf(p + 1, "%4x", &cp) != 1) goto malformed;
        p += 5;
        if (cp >= 0xD800 && cp <= 0xDBFF && p[0] == '\\' && p[1] == 'u') {
          unsigned lo;
          if (sscanf(p + 2, "%4x", &lo) != 1) goto malformed;
          if (lo >= 0xDC00 && lo <= 0xDFFF) {
            cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
            p += 6;
          }
        }
        if (cp < 0x80) {
          out[n++] = (char)cp;
        } else if (cp < 0x800) {
          out[n++] = (char)(0xC0 | (cp >> 6));
          out[n++] = (char)(0x80 | (cp & 0x3F));
        } else if (cp < 0x10000) {
          out[n++] = (char)(0xE0 | (cp >> 12));
          out[n++] = (char)(0x80 | ((cp >> 6) & 0x3F));
          out[n++] = (char)(0x80 | (cp & 0x3F));
        } else {
          out[n++] = (char)(0xF0 | (cp >> 18));
          out[n++] = (char)(0x80 | ((cp >> 12) & 0x3F));
          out[n++] = (char)(0x80 | ((cp >> 6) & 0x3F));
          out[n++] = (char)(0x80 | (cp & 0x3F));
        }
        break;
      }
      default: goto malformed;
      }
    } else {
      out[n++] = *p++;
    }
  }
  if (*p != '"') goto malformed;
  out[n] = '\0';
  return out;

malformed:
  free(out);
  return NULL;
}

static void json_print_escaped(const char *s) {
  for (const unsigned char *p = (const unsigned char *)s; *p; p++) {
    switch (*p) {
    case '"': fputs("\\\"", stdout); break;
    case '\\': fputs("\\\\", stdout); break;
    case '\n': fputs("\\n", stdout); break;
    case '\r': fputs("\\r", stdout); break;
    case '\t': fputs("\\t", stdout); break;
    default:
      if (*p < 0x20)
        printf("\\u%04x", *p);
      else
        fputc(*p, stdout);
    }
  }
}

static void respond_error(const char *message) {
  fputs("{\"ok\":false,\"error\":\"", stdout);
  json_print_escaped(message);
  fputs("\"}\n", stdout);
  fflush(stdout);
}

static void respond_ok_text(const char *key, const char *value) {
  fputs("{\"ok\":true", stdout);
  if (key) {
    printf(",\"%s\":\"", key);
    json_print_escaped(value);
    fputs("\"", stdout);
  }
  fputs("}\n", stdout);
  fflush(stdout);
}

/* --- slots --------------------------------------------------------------- */

static sk_slot *find_slot(const char *name) {
  for (int i = 0; i < SK_MAX_SLOTS; i++) {
    if (slots[i].model && strcmp(slots[i].name, name) == 0) return &slots[i];
  }
  return NULL;
}

static sk_slot *claim_slot(void) {
  sk_slot *lru = &slots[0];
  for (int i = 0; i < SK_MAX_SLOTS; i++) {
    if (!slots[i].model) return &slots[i];
    if (slots[i].last_used < lru->last_used) lru = &slots[i];
  }
  sk_nn_free(lru->model);
  lru->model = NULL;
  return lru;
}

/* --- ops ------------------------------------------------------------------ */

static void op_load(const char *line) {
  char err[256] = "unknown error";
  char *slot_name = json_get_string(line, "slot");
  char *model_path = json_get_string(line, "model");
  char *vocab_path = json_get_string(line, "vocab");
  if (!slot_name || !model_path || !vocab_path ||
      strlen(slot_name) >= sizeof(slots[0].name)) {
    respond_error("load requires slot, model and vocab");
    goto done;
  }
  if (find_slot(slot_name)) {
    respond_ok_text(NULL, NULL); /* already resident */
    goto done;
  }

  sk_model_file *mf = sk_model_file_load(model_path, err, sizeof(err));
  if (!mf) {
    respond_error(err);
    goto done;
  }
  sk_vocab *vocab = sk_vocab_load(vocab_path, err, sizeof(err));
  if (!vocab) {
    sk_model_file_free(mf);
    respond_error(err);
    goto done;
  }
  sk_nn *model = sk_nn_create(mf, vocab, err, sizeof(err));
  if (!model) {
    sk_model_file_free(mf);
    sk_vocab_free(vocab);
    respond_error(err);
    goto done;
  }

  sk_slot *slot = claim_slot();
  snprintf(slot->name, sizeof(slot->name), "%s", slot_name);
  slot->model = model;
  slot->last_used = ++use_counter;
  respond_ok_text(NULL, NULL);

done:
  free(slot_name);
  free(model_path);
  free(vocab_path);
}

static void op_translate(const char *line) {
  char err[256] = "unknown error";
  char *slot_name = json_get_string(line, "slot");
  char *text = json_get_string(line, "text");
  if (!slot_name || !text) {
    respond_error("translate requires slot and text");
    goto done;
  }
  sk_slot *slot = find_slot(slot_name);
  if (!slot) {
    respond_error("model is not loaded");
    goto done;
  }
  slot->last_used = ++use_counter;
  char *result = sk_nn_translate(slot->model, text, err, sizeof(err));
  if (!result) {
    respond_error(err);
    goto done;
  }
  respond_ok_text("text", result);
  free(result);

done:
  free(slot_name);
  free(text);
}

static void op_unload(const char *line) {
  char *slot_name = json_get_string(line, "slot");
  if (slot_name) {
    sk_slot *slot = find_slot(slot_name);
    if (slot) {
      sk_nn_free(slot->model);
      slot->model = NULL;
    }
  }
  free(slot_name);
  respond_ok_text(NULL, NULL);
}

int main(void) {
  char *line = NULL;
  size_t cap = 0;
  ssize_t len;

  while ((len = getline(&line, &cap, stdin)) != -1) {
    if (len > SK_MAX_LINE) {
      respond_error("request too large");
      continue;
    }
    char *op = json_get_string(line, "op");
    if (!op) {
      respond_error("missing op");
    } else if (strcmp(op, "ping") == 0) {
      respond_ok_text("version", SK_ENGINE_VERSION);
    } else if (strcmp(op, "load") == 0) {
      op_load(line);
    } else if (strcmp(op, "translate") == 0) {
      op_translate(line);
    } else if (strcmp(op, "unload") == 0) {
      op_unload(line);
    } else {
      respond_error("unknown op");
    }
    free(op);
  }

  free(line);
  for (int i = 0; i < SK_MAX_SLOTS; i++) sk_nn_free(slots[i].model);
  return 0;
}
