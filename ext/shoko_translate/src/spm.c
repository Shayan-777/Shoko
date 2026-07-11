#include "spm.h"

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* SentencePiece ModelProto, field 1 (repeated SentencePiece):
 *   1: piece (string), 2: score (float), 3: type (enum)
 * piece types: 1=NORMAL 2=UNKNOWN 3=CONTROL 4=USER_DEFINED 5=UNUSED 6=BYTE */
#define SK_PIECE_NORMAL 1
#define SK_PIECE_UNKNOWN 2
#define SK_PIECE_CONTROL 3
#define SK_PIECE_USER_DEFINED 4
#define SK_PIECE_BYTE 6

#define SK_MAX_TEXT_BYTES 16384
#define SK_WS "\xE2\x96\x81" /* U+2581 lower one eighth block */

typedef struct {
  char *bytes;
  int len;
  float score;
  int type;
} sk_piece;

struct sk_vocab {
  sk_piece *pieces;
  int count;
  int unk_id;
  float unk_score;
  int max_piece_len;
  /* open-addressing hash of scorable pieces -> id */
  int *slots;
  uint32_t mask;
};

static void set_err(char *err, size_t errsz, const char *msg) {
  if (err && errsz) snprintf(err, errsz, "%s", msg);
}

static uint32_t fnv1a(const char *s, int len) {
  uint32_t h = 2166136261u;
  for (int i = 0; i < len; i++) {
    h ^= (unsigned char)s[i];
    h *= 16777619u;
  }
  return h;
}

static int piece_lookup(const sk_vocab *v, const char *s, int len) {
  uint32_t idx = fnv1a(s, len) & v->mask;
  for (;;) {
    int id = v->slots[idx];
    if (id < 0) return -1;
    if (v->pieces[id].len == len && memcmp(v->pieces[id].bytes, s, len) == 0)
      return id;
    idx = (idx + 1) & v->mask;
  }
}

/* --- protobuf wire helpers ------------------------------------------- */

typedef struct {
  const unsigned char *p;
  size_t len;
  size_t off;
  int error;
} sk_pb;

static uint64_t pb_varint(sk_pb *b) {
  uint64_t result = 0;
  int shift = 0;
  while (b->off < b->len && shift < 64) {
    unsigned char byte = b->p[b->off++];
    result |= (uint64_t)(byte & 0x7F) << shift;
    if (!(byte & 0x80)) return result;
    shift += 7;
  }
  b->error = 1;
  return 0;
}

static void pb_skip(sk_pb *b, int wire) {
  switch (wire) {
  case 0: pb_varint(b); break;
  case 1: b->off += 8; break;
  case 2: {
    uint64_t n = pb_varint(b);
    b->off += n;
    break;
  }
  case 5: b->off += 4; break;
  default: b->error = 1;
  }
  if (b->off > b->len) b->error = 1;
}

/* --- loading ---------------------------------------------------------- */

static int parse_one_piece(sk_pb *b, uint64_t msg_len, sk_piece *out) {
  size_t end = b->off + msg_len;
  if (end > b->len) return 0;
  out->bytes = NULL;
  out->len = 0;
  out->score = 0.0f;
  out->type = SK_PIECE_NORMAL;
  while (b->off < end && !b->error) {
    uint64_t key = pb_varint(b);
    int field = (int)(key >> 3), wire = (int)(key & 7);
    if (field == 1 && wire == 2) {
      uint64_t n = pb_varint(b);
      if (b->off + n > end || n > 512) return 0;
      out->bytes = malloc(n + 1);
      if (!out->bytes) return 0;
      memcpy(out->bytes, b->p + b->off, n);
      out->bytes[n] = '\0';
      out->len = (int)n;
      b->off += n;
    } else if (field == 2 && wire == 5) {
      if (b->off + 4 > end) return 0;
      memcpy(&out->score, b->p + b->off, 4);
      b->off += 4;
    } else if (field == 3 && wire == 0) {
      out->type = (int)pb_varint(b);
    } else {
      pb_skip(b, wire);
    }
  }
  return !b->error && out->bytes != NULL;
}

static unsigned char *read_whole_file(const char *path, size_t *size_out) {
  FILE *f = fopen(path, "rb");
  if (!f) return NULL;
  if (fseek(f, 0, SEEK_END) != 0) {
    fclose(f);
    return NULL;
  }
  long size = ftell(f);
  if (size <= 0) {
    fclose(f);
    return NULL;
  }
  rewind(f);
  unsigned char *buf = malloc((size_t)size);
  if (buf && fread(buf, 1, (size_t)size, f) != (size_t)size) {
    free(buf);
    buf = NULL;
  }
  fclose(f);
  if (buf) *size_out = (size_t)size;
  return buf;
}

sk_vocab *sk_vocab_load(const char *path, char *err, size_t errsz) {
  size_t size = 0;
  unsigned char *buf = read_whole_file(path, &size);
  if (!buf) {
    set_err(err, errsz, "cannot read vocabulary file");
    return NULL;
  }

  sk_vocab *v = calloc(1, sizeof(*v));
  int capacity = 0;
  if (!v) goto fail_oom;
  v->unk_id = -1;

  sk_pb b = {buf, size, 0, 0};
  while (b.off < b.len && !b.error) {
    uint64_t key = pb_varint(&b);
    int field = (int)(key >> 3), wire = (int)(key & 7);
    if (field == 1 && wire == 2) {
      uint64_t n = pb_varint(&b);
      if (v->count == capacity) {
        capacity = capacity ? capacity * 2 : 1024;
        sk_piece *grown = realloc(v->pieces, capacity * sizeof(sk_piece));
        if (!grown) goto fail_oom;
        v->pieces = grown;
      }
      if (!parse_one_piece(&b, n, &v->pieces[v->count])) {
        set_err(err, errsz, "malformed vocabulary file");
        goto fail;
      }
      v->count++;
    } else {
      pb_skip(&b, wire);
    }
  }
  if (b.error || v->count < 3) {
    set_err(err, errsz, "malformed vocabulary file");
    goto fail;
  }

  float min_score = 0.0f;
  for (int i = 0; i < v->count; i++) {
    sk_piece *p = &v->pieces[i];
    if (p->type == SK_PIECE_UNKNOWN) v->unk_id = i;
    if (p->score < min_score) min_score = p->score;
    if (p->len > v->max_piece_len) v->max_piece_len = p->len;
  }
  if (v->unk_id < 0) {
    set_err(err, errsz, "vocabulary has no <unk> piece");
    goto fail;
  }
  v->unk_score = min_score - 10.0f;

  uint32_t table = 1;
  while (table < (uint32_t)v->count * 4) table <<= 1;
  v->mask = table - 1;
  v->slots = malloc(table * sizeof(int));
  if (!v->slots) goto fail_oom;
  for (uint32_t i = 0; i < table; i++) v->slots[i] = -1;
  for (int i = 0; i < v->count; i++) {
    sk_piece *p = &v->pieces[i];
    if (p->type != SK_PIECE_NORMAL && p->type != SK_PIECE_USER_DEFINED &&
        p->type != SK_PIECE_BYTE)
      continue;
    uint32_t idx = fnv1a(p->bytes, p->len) & v->mask;
    while (v->slots[idx] >= 0) idx = (idx + 1) & v->mask;
    v->slots[idx] = i;
  }

  free(buf);
  return v;

fail_oom:
  set_err(err, errsz, "out of memory loading vocabulary");
fail:
  free(buf);
  sk_vocab_free(v);
  return NULL;
}

void sk_vocab_free(sk_vocab *v) {
  if (!v) return;
  for (int i = 0; i < v->count; i++) free(v->pieces[i].bytes);
  free(v->pieces);
  free(v->slots);
  free(v);
}

int sk_vocab_size(const sk_vocab *v) { return v->count; }

/* --- encoding ---------------------------------------------------------- */

static int is_cp_start(unsigned char c) { return (c & 0xC0) != 0x80; }

static int cp_len(const char *s) {
  unsigned char c = (unsigned char)s[0];
  if (c < 0x80) return 1;
  if ((c & 0xE0) == 0xC0) return 2;
  if ((c & 0xF0) == 0xE0) return 3;
  if ((c & 0xF8) == 0xF0) return 4;
  return 1; /* invalid byte: step over it */
}

int sk_vocab_encode(const sk_vocab *v, const char *text, int *ids,
                    int max_ids) {
  size_t text_len = strlen(text);
  if (text_len == 0) return 0;
  if (text_len > SK_MAX_TEXT_BYTES) return -1;

  /* build "▁" + text with ' ' replaced by ▁ */
  char *s = malloc(text_len * 3 + 4);
  if (!s) return -1;
  int n = 0;
  memcpy(s + n, SK_WS, 3);
  n += 3;
  for (size_t i = 0; i < text_len; i++) {
    if (text[i] == ' ') {
      memcpy(s + n, SK_WS, 3);
      n += 3;
    } else {
      s[n++] = text[i];
    }
  }
  s[n] = '\0';

  float *best = malloc((n + 1) * sizeof(float));
  int *back_start = malloc((n + 1) * sizeof(int));
  int *back_id = malloc((n + 1) * sizeof(int));
  if (!best || !back_start || !back_id) {
    free(s);
    free(best);
    free(back_start);
    free(back_id);
    return -1;
  }
  for (int i = 0; i <= n; i++) {
    best[i] = -INFINITY;
    back_start[i] = -1;
  }
  best[0] = 0.0f;

  for (int i = 0; i < n; i++) {
    if (best[i] == -INFINITY || !is_cp_start((unsigned char)s[i])) continue;
    int limit = v->max_piece_len;
    if (limit > n - i) limit = n - i;
    for (int len = 1; len <= limit; len++) {
      int end = i + len;
      if (end < n && !is_cp_start((unsigned char)s[end])) continue;
      int id = piece_lookup(v, s + i, len);
      if (id < 0) continue;
      float sc = best[i] + v->pieces[id].score;
      if (sc > best[end]) {
        best[end] = sc;
        back_start[end] = i;
        back_id[end] = id;
      }
    }
    /* unknown fallback: one codepoint as <unk> */
    int step = cp_len(s + i);
    if (i + step > n) step = n - i;
    float sc = best[i] + v->unk_score;
    if (sc > best[i + step]) {
      best[i + step] = sc;
      back_start[i + step] = i;
      back_id[i + step] = v->unk_id;
    }
  }

  int count = 0;
  int ok = best[n] != -INFINITY;
  if (ok) {
    /* walk back to count, then fill forward */
    int pos = n;
    while (pos > 0) {
      count++;
      pos = back_start[pos];
    }
    if (count > max_ids) {
      ok = 0;
    } else {
      pos = n;
      int w = count;
      while (pos > 0) {
        ids[--w] = back_id[pos];
        pos = back_start[pos];
      }
    }
  }

  free(s);
  free(best);
  free(back_start);
  free(back_id);
  return ok ? count : -1;
}

char *sk_vocab_decode(const sk_vocab *v, const int *ids, int count) {
  size_t total = 1;
  for (int i = 0; i < count; i++) {
    if (ids[i] < 0 || ids[i] >= v->count) continue;
    total += v->pieces[ids[i]].len;
  }
  char *out = malloc(total);
  if (!out) return NULL;
  int n = 0;
  for (int i = 0; i < count; i++) {
    if (ids[i] < 0 || ids[i] >= v->count) continue;
    const sk_piece *p = &v->pieces[ids[i]];
    if (p->type == SK_PIECE_CONTROL || p->type == SK_PIECE_UNKNOWN) continue;
    memcpy(out + n, p->bytes, p->len);
    n += p->len;
  }
  out[n] = '\0';
  /* replace ▁ (E2 96 81) with spaces, in place */
  int r = 0, w = 0;
  while (out[r]) {
    if ((unsigned char)out[r] == 0xE2 && (unsigned char)out[r + 1] == 0x96 &&
        (unsigned char)out[r + 2] == 0x81) {
      out[w++] = ' ';
      r += 3;
    } else {
      out[w++] = out[r++];
    }
  }
  out[w] = '\0';
  /* trim leading space introduced by the dummy prefix */
  if (out[0] == ' ') memmove(out, out + 1, w);
  return out;
}
