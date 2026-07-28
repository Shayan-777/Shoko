/* shoko-translate: offline translation engine for Shoko.
 *
 * Speaks a deliberately small JSON-lines protocol over stdin/stdout. Requests
 * are flat objects whose values are strings. One request produces exactly one
 * response, and malformed input never changes engine state.
 */
#define _POSIX_C_SOURCE 200809L

#include <ctype.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "marian_bin.h"
#include "nn.h"
#include "spm.h"

#define SK_ENGINE_VERSION "1.1.0"
#define SK_MAX_SLOTS 4
#define SK_MAX_LINE (1 << 20)

typedef struct {
  char name[64];
  char *model_path;
  char *vocab_path;
  sk_nn *model;
  unsigned long last_used;
} sk_slot;

typedef struct {
  char *op;
  char *slot;
  char *model;
  char *vocab;
  char *text;
} sk_request;

static sk_slot slots[SK_MAX_SLOTS];
static unsigned long use_counter;

/* --- strict flat-JSON parser -------------------------------------------- */

static void skip_ws(const char **p) {
  while (**p == ' ' || **p == '\t' || **p == '\r' || **p == '\n') (*p)++;
}

static int hex_digit(unsigned char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}

static int read_hex4(const char **p, unsigned *value) {
  unsigned v = 0;
  for (int i = 0; i < 4; i++) {
    int digit = hex_digit((unsigned char)(*p)[i]);
    if (digit < 0) return 0;
    v = (v << 4) | (unsigned)digit;
  }
  *p += 4;
  *value = v;
  return 1;
}

static int append_utf8(char *out, size_t *n, unsigned cp) {
  if (cp == 0 || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF))
    return 0;
  if (cp < 0x80) {
    out[(*n)++] = (char)cp;
  } else if (cp < 0x800) {
    out[(*n)++] = (char)(0xC0 | (cp >> 6));
    out[(*n)++] = (char)(0x80 | (cp & 0x3F));
  } else if (cp < 0x10000) {
    out[(*n)++] = (char)(0xE0 | (cp >> 12));
    out[(*n)++] = (char)(0x80 | ((cp >> 6) & 0x3F));
    out[(*n)++] = (char)(0x80 | (cp & 0x3F));
  } else {
    out[(*n)++] = (char)(0xF0 | (cp >> 18));
    out[(*n)++] = (char)(0x80 | ((cp >> 12) & 0x3F));
    out[(*n)++] = (char)(0x80 | ((cp >> 6) & 0x3F));
    out[(*n)++] = (char)(0x80 | (cp & 0x3F));
  }
  return 1;
}

static int valid_utf8(const char *text, size_t length) {
  const unsigned char *p = (const unsigned char *)text;
  const unsigned char *end = p + length;
  while (p < end) {
    if (*p < 0x80) {
      p++;
    } else if (end - p >= 2 && *p >= 0xC2 && *p <= 0xDF &&
               p[1] >= 0x80 && p[1] <= 0xBF) {
      p += 2;
    } else if (end - p >= 3 && *p == 0xE0 &&
               p[1] >= 0xA0 && p[1] <= 0xBF &&
               p[2] >= 0x80 && p[2] <= 0xBF) {
      p += 3;
    } else if (end - p >= 3 &&
               ((*p >= 0xE1 && *p <= 0xEC) ||
                (*p >= 0xEE && *p <= 0xEF)) &&
               p[1] >= 0x80 && p[1] <= 0xBF &&
               p[2] >= 0x80 && p[2] <= 0xBF) {
      p += 3;
    } else if (end - p >= 3 && *p == 0xED &&
               p[1] >= 0x80 && p[1] <= 0x9F &&
               p[2] >= 0x80 && p[2] <= 0xBF) {
      p += 3;
    } else if (end - p >= 4 && *p == 0xF0 &&
               p[1] >= 0x90 && p[1] <= 0xBF &&
               p[2] >= 0x80 && p[2] <= 0xBF &&
               p[3] >= 0x80 && p[3] <= 0xBF) {
      p += 4;
    } else if (end - p >= 4 && *p >= 0xF1 && *p <= 0xF3 &&
               p[1] >= 0x80 && p[1] <= 0xBF &&
               p[2] >= 0x80 && p[2] <= 0xBF &&
               p[3] >= 0x80 && p[3] <= 0xBF) {
      p += 4;
    } else if (end - p >= 4 && *p == 0xF4 &&
               p[1] >= 0x80 && p[1] <= 0x8F &&
               p[2] >= 0x80 && p[2] <= 0xBF &&
               p[3] >= 0x80 && p[3] <= 0xBF) {
      p += 4;
    } else {
      return 0;
    }
  }
  return 1;
}

static int parse_json_string(const char **cursor, char **value) {
  const char *p = *cursor;
  if (*p++ != '"') return 0;
  size_t cap = strlen(p) + 1;
  char *out = malloc(cap);
  if (!out) return -1;
  size_t n = 0;

  while (*p && *p != '"') {
    unsigned char c = (unsigned char)*p++;
    if (c < 0x20) goto malformed;
    if (c != '\\') {
      out[n++] = (char)c;
      continue;
    }

    c = (unsigned char)*p++;
    switch (c) {
    case '"': out[n++] = '"'; break;
    case '\\': out[n++] = '\\'; break;
    case '/': out[n++] = '/'; break;
    case 'b': out[n++] = '\b'; break;
    case 'f': out[n++] = '\f'; break;
    case 'n': out[n++] = '\n'; break;
    case 'r': out[n++] = '\r'; break;
    case 't': out[n++] = '\t'; break;
    case 'u': {
      unsigned cp;
      if (!read_hex4(&p, &cp)) goto malformed;
      if (cp >= 0xD800 && cp <= 0xDBFF) {
        unsigned lo;
        if (p[0] != '\\' || p[1] != 'u') goto malformed;
        p += 2;
        if (!read_hex4(&p, &lo) || lo < 0xDC00 || lo > 0xDFFF)
          goto malformed;
        cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
      } else if (cp >= 0xDC00 && cp <= 0xDFFF) {
        goto malformed;
      }
      if (!append_utf8(out, &n, cp)) goto malformed;
      break;
    }
    default: goto malformed;
    }
  }
  if (*p != '"') goto malformed;
  p++;
  out[n] = '\0';
  if (!valid_utf8(out, n)) goto malformed;
  *cursor = p;
  *value = out;
  return 1;

malformed:
  free(out);
  return 0;
}

static char **request_field(sk_request *request, const char *key) {
  if (strcmp(key, "op") == 0) return &request->op;
  if (strcmp(key, "slot") == 0) return &request->slot;
  if (strcmp(key, "model") == 0) return &request->model;
  if (strcmp(key, "vocab") == 0) return &request->vocab;
  if (strcmp(key, "text") == 0) return &request->text;
  return NULL;
}

static int parse_request(const char *line, sk_request *request) {
  const char *p = line;
  skip_ws(&p);
  if (*p++ != '{') return 0;
  skip_ws(&p);
  if (*p == '}') {
    p++;
    skip_ws(&p);
    return *p == '\0';
  }

  for (;;) {
    char *key = NULL, *value = NULL;
    int status = parse_json_string(&p, &key);
    if (status <= 0) {
      free(key);
      return status;
    }
    skip_ws(&p);
    if (*p++ != ':') {
      free(key);
      return 0;
    }
    skip_ws(&p);
    status = parse_json_string(&p, &value);
    if (status <= 0) {
      free(key);
      free(value);
      return status;
    }

    char **field = request_field(request, key);
    free(key);
    if (field) {
      if (*field) {
        free(value);
        return 0; /* duplicate known fields are ambiguous */
      }
      *field = value;
    } else {
      free(value);
      return 0; /* reject typos and unsupported protocol fields */
    }

    skip_ws(&p);
    if (*p == ',') {
      p++;
      skip_ws(&p);
      continue;
    }
    if (*p++ != '}') return 0;
    skip_ws(&p);
    return *p == '\0';
  }
}

static void request_free(sk_request *request) {
  free(request->op);
  free(request->slot);
  free(request->model);
  free(request->vocab);
  free(request->text);
  memset(request, 0, sizeof(*request));
}

/* --- responses ----------------------------------------------------------- */

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

static void respond_error(const char *code, const char *message) {
  fputs("{\"ok\":false,\"code\":\"", stdout);
  json_print_escaped(code);
  fputs("\",\"error\":\"", stdout);
  json_print_escaped(message);
  fputs("\"}\n", stdout);
  fflush(stdout);
}

static void respond_ok(void) {
  fputs("{\"ok\":true}\n", stdout);
  fflush(stdout);
}

static void respond_ping(void) {
  printf("{\"ok\":true,\"version\":\"%s\",\"max_slots\":%d}\n",
         SK_ENGINE_VERSION, SK_MAX_SLOTS);
  fflush(stdout);
}

static void respond_load(const char *evicted) {
  fputs("{\"ok\":true", stdout);
  if (evicted && *evicted) {
    fputs(",\"evicted\":\"", stdout);
    json_print_escaped(evicted);
    fputc('"', stdout);
  }
  fputs("}\n", stdout);
  fflush(stdout);
}

static void respond_translation(const char *text, int truncated) {
  fputs("{\"ok\":true,\"text\":\"", stdout);
  json_print_escaped(text);
  fputs("\",\"finish_reason\":\"", stdout);
  fputs(truncated ? "max_tokens" : "eos", stdout);
  fputs("\"}\n", stdout);
  fflush(stdout);
}

/* --- slots --------------------------------------------------------------- */

static void clear_slot(sk_slot *slot) {
  if (!slot) return;
  sk_nn_free(slot->model);
  free(slot->model_path);
  free(slot->vocab_path);
  memset(slot, 0, sizeof(*slot));
}

static sk_slot *find_slot(const char *name) {
  for (int i = 0; i < SK_MAX_SLOTS; i++) {
    if (slots[i].model && strcmp(slots[i].name, name) == 0) return &slots[i];
  }
  return NULL;
}

static int same_model(const sk_slot *slot, const char *model, const char *vocab) {
  return slot && slot->model_path && slot->vocab_path &&
         strcmp(slot->model_path, model) == 0 &&
         strcmp(slot->vocab_path, vocab) == 0;
}

static sk_slot *select_slot(char evicted[64]) {
  sk_slot *lru = &slots[0];
  evicted[0] = '\0';
  for (int i = 0; i < SK_MAX_SLOTS; i++) {
    if (!slots[i].model) return &slots[i];
    if (slots[i].last_used < lru->last_used) lru = &slots[i];
  }
  snprintf(evicted, 64, "%s", lru->name);
  return lru;
}

/* --- operations ---------------------------------------------------------- */

static void op_load(const sk_request *request) {
  char err[256] = "unknown error";
  if (!request->slot || !*request->slot || !request->model ||
      !*request->model || !request->vocab || !*request->vocab ||
      strlen(request->slot) >= sizeof(slots[0].name)) {
    respond_error("invalid_request", "load requires slot, model and vocab");
    return;
  }

  sk_slot *existing = find_slot(request->slot);
  if (same_model(existing, request->model, request->vocab)) {
    existing->last_used = ++use_counter;
    respond_load(NULL);
    return;
  }

  sk_model_file *mf = sk_model_file_load(request->model, err, sizeof(err));
  if (!mf) {
    respond_error("model_load_failed", err);
    return;
  }
  sk_vocab *vocab = sk_vocab_load(request->vocab, err, sizeof(err));
  if (!vocab) {
    sk_model_file_free(mf);
    respond_error("vocab_load_failed", err);
    return;
  }
  sk_nn *model = sk_nn_create(mf, vocab, err, sizeof(err));
  if (!model) {
    sk_model_file_free(mf);
    sk_vocab_free(vocab);
    respond_error("model_incompatible", err);
    return;
  }

  char *model_path = strdup(request->model);
  char *vocab_path = strdup(request->vocab);
  if (!model_path || !vocab_path) {
    free(model_path);
    free(vocab_path);
    sk_nn_free(model);
    respond_error("out_of_memory", "out of memory recording model identity");
    return;
  }

  char evicted[64];
  sk_slot *slot = existing;
  if (slot) {
    snprintf(evicted, sizeof(evicted), "%s", slot->name);
  } else {
    slot = select_slot(evicted);
  }
  clear_slot(slot);
  slot->model_path = model_path;
  slot->vocab_path = vocab_path;
  snprintf(slot->name, sizeof(slot->name), "%s", request->slot);
  slot->model = model;
  slot->last_used = ++use_counter;
  respond_load(evicted);
}

static void op_translate(const sk_request *request) {
  char err[256] = "unknown error";
  if (!request->slot || !request->text) {
    respond_error("invalid_request", "translate requires slot and text");
    return;
  }
  sk_slot *slot = find_slot(request->slot);
  if (!slot) {
    respond_error("model_not_loaded", "model is not loaded");
    return;
  }
  slot->last_used = ++use_counter;
  int truncated = 0;
  char *result = sk_nn_translate(slot->model, request->text, &truncated,
                                 err, sizeof(err));
  if (!result) {
    respond_error("translation_failed", err);
    return;
  }
  respond_translation(result, truncated);
  free(result);
}

static void op_unload(const sk_request *request) {
  if (!request->slot) {
    respond_error("invalid_request", "unload requires slot");
    return;
  }
  clear_slot(find_slot(request->slot));
  respond_ok();
}

static void dispatch_request(const sk_request *request) {
  if (!request->op) {
    respond_error("invalid_request", "missing op");
  } else if (strcmp(request->op, "ping") == 0) {
    respond_ping();
  } else if (strcmp(request->op, "load") == 0) {
    op_load(request);
  } else if (strcmp(request->op, "translate") == 0) {
    op_translate(request);
  } else if (strcmp(request->op, "unload") == 0) {
    op_unload(request);
  } else {
    respond_error("unknown_operation", "unknown op");
  }
}

int main(void) {
  char *line = malloc(SK_MAX_LINE + 2);
  if (!line) return 1;

  while (fgets(line, SK_MAX_LINE + 2, stdin)) {
    size_t len = strlen(line);
    int complete = len > 0 && line[len - 1] == '\n';
    if (!complete && !feof(stdin)) {
      int ch;
      while ((ch = fgetc(stdin)) != '\n' && ch != EOF) {}
      respond_error("request_too_large", "request too large");
      continue;
    }
    if (complete) line[--len] = '\0';
    if (len > 0 && line[len - 1] == '\r') line[--len] = '\0';

    sk_request request = {0};
    int parsed = parse_request(line, &request);
    if (parsed < 0)
      respond_error("out_of_memory", "out of memory parsing request");
    else if (!parsed)
      respond_error("malformed_json", "request must be a flat JSON object with string values");
    else
      dispatch_request(&request);
    request_free(&request);
  }

  free(line);
  for (int i = 0; i < SK_MAX_SLOTS; i++) clear_slot(&slots[i]);
  return 0;
}
