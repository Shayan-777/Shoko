#include "marian_bin.h"

#include <inttypes.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SK_TYPE_INTGEMM8 0x4101u
#define SK_TYPE_FLOAT32 0x404u
#define SK_MAX_MODEL_BYTES ((uintmax_t)2 * 1024 * 1024 * 1024)
#define SK_MAX_CONFIG_BYTES ((uint64_t)1024 * 1024)

typedef struct {
  uint64_t name_len;
  uint64_t type;
  uint64_t shape_len;
  uint64_t data_len;
} sk_bin_header;

static void set_err(char *err, size_t errsz, const char *msg) {
  if (err && errsz) snprintf(err, errsz, "%s", msg);
}

static int host_is_little_endian(void) {
  const uint16_t probe = 1;
  return *(const uint8_t *)&probe == 1;
}

static uint64_t read_u64(const unsigned char *p) {
  uint64_t v;
  memcpy(&v, p, sizeof(v));
  return v;
}

static unsigned char *read_whole_file(const char *path, size_t *size_out,
                                      char *err, size_t errsz) {
  FILE *f = fopen(path, "rb");
  if (!f) {
    set_err(err, errsz, "cannot open model file");
    return NULL;
  }
  if (fseek(f, 0, SEEK_END) != 0) {
    fclose(f);
    set_err(err, errsz, "cannot seek model file");
    return NULL;
  }
  long size = ftell(f);
  if (size <= 0 || (uintmax_t)size > SK_MAX_MODEL_BYTES) {
    fclose(f);
    set_err(err, errsz, "empty model file");
    return NULL;
  }
  rewind(f);
  unsigned char *buf = malloc((size_t)size);
  if (!buf) {
    fclose(f);
    set_err(err, errsz, "out of memory reading model file");
    return NULL;
  }
  if (fread(buf, 1, (size_t)size, f) != (size_t)size) {
    fclose(f);
    free(buf);
    set_err(err, errsz, "short read on model file");
    return NULL;
  }
  fclose(f);
  *size_out = (size_t)size;
  return buf;
}

/* Collapses an n-dim shape to stored (rows, cols): cols = trailing dim,
 * rows = product of the rest. Returns 0 on overflow/invalid dims. */
static int collapse_shape(const int32_t *dims, uint64_t ndims, int *rows,
                          int *cols) {
  if (ndims == 0) return 0;
  int64_t r = 1;
  for (uint64_t i = 0; i + 1 < ndims; i++) {
    if (dims[i] <= 0) return 0;
    r *= dims[i];
    if (r > INT32_MAX) return 0;
  }
  int32_t c = dims[ndims - 1];
  if (c <= 0) return 0;
  if (r * c > (int64_t)1 << 31) return 0;
  *rows = (int)r;
  *cols = (int)c;
  return 1;
}

static int is_wemb_name(const char *name) {
  return strstr(name, "Wemb") != NULL;
}

static int payload_matches(const unsigned char *data, uint64_t stored,
                           uint64_t payload) {
  if (stored == payload) return 1;
  if (payload > UINT64_MAX - 255) return 0;
  uint64_t aligned = (payload + 255) & ~UINT64_C(255);
  if (stored != aligned) return 0;
  for (uint64_t i = payload; i < stored; i++)
    if (data[i] != 0) return 0;
  return 1;
}

sk_model_file *sk_model_file_load(const char *path, char *err, size_t errsz) {
  if (!host_is_little_endian()) {
    set_err(err, errsz, "big-endian hosts are not supported");
    return NULL;
  }
  size_t size = 0;
  unsigned char *buf = read_whole_file(path, &size, err, errsz);
  if (!buf) return NULL;

  sk_model_file *mf = NULL;
  sk_bin_header *headers = NULL;
  size_t off = 0;

#define NEED(n)                                        \
  do {                                                 \
    if (size - off < (uint64_t)(n)) goto fail_truncated; \
  } while (0)

  NEED(16);
  uint64_t version = read_u64(buf + off);
  uint64_t count = read_u64(buf + off + 8);
  off += 16;
  if (version != 1) {
    set_err(err, errsz, "unsupported model binary version");
    goto fail;
  }
  if (count == 0 || count > 4096) {
    set_err(err, errsz, "implausible tensor count in model file");
    goto fail;
  }

  headers = malloc(count * sizeof(*headers));
  mf = calloc(1, sizeof(*mf));
  if (!headers || !mf) goto fail_oom;
  mf->tensors = calloc(count, sizeof(sk_tensor));
  if (!mf->tensors) goto fail_oom;
  mf->count = (int)count; /* slots are zeroed; free is safe from here on */

  NEED(count * 32);
  for (uint64_t i = 0; i < count; i++) {
    headers[i].name_len = read_u64(buf + off);
    headers[i].type = read_u64(buf + off + 8);
    headers[i].shape_len = read_u64(buf + off + 16);
    headers[i].data_len = read_u64(buf + off + 24);
    off += 32;
    if (headers[i].name_len == 0 || headers[i].name_len > 512 ||
        headers[i].shape_len > 8) {
      set_err(err, errsz, "implausible tensor header in model file");
      goto fail;
    }
  }

  for (uint64_t i = 0; i < count; i++) {
    NEED(headers[i].name_len);
    char *name = malloc(headers[i].name_len);
    if (!name) goto fail_oom;
    memcpy(name, buf + off, headers[i].name_len);
    if (name[headers[i].name_len - 1] != '\0' ||
        memchr(name, '\0', (size_t)headers[i].name_len - 1) != NULL) {
      free(name);
      set_err(err, errsz, "invalid tensor name in model file");
      goto fail;
    }
    for (uint64_t previous = 0; previous < i; previous++) {
      if (strcmp(mf->tensors[previous].name, name) == 0) {
        free(name);
        set_err(err, errsz, "duplicate tensor name in model file");
        goto fail;
      }
    }
    mf->tensors[i].name = name;
    off += headers[i].name_len;
  }

  int32_t shapes[4096][8];
  for (uint64_t i = 0; i < count; i++) {
    NEED(headers[i].shape_len * 4);
    memcpy(shapes[i], buf + off, headers[i].shape_len * 4);
    off += headers[i].shape_len * 4;
  }

  NEED(8);
  uint64_t pad = read_u64(buf + off);
  off += 8;
  NEED(pad);
  off += pad;

  for (uint64_t i = 0; i < count; i++) {
    sk_bin_header *h = &headers[i];
    sk_tensor *t = &mf->tensors[i];
    NEED(h->data_len);
    const unsigned char *data = buf + off;
    off += h->data_len;

    if (strcmp(t->name, "special:model.yml") == 0) {
      if (h->data_len > SK_MAX_CONFIG_BYTES) {
        set_err(err, errsz, "embedded model config is too large");
        goto fail;
      }
      mf->config_yml = malloc(h->data_len + 1);
      if (!mf->config_yml) goto fail_oom;
      memcpy(mf->config_yml, data, h->data_len);
      mf->config_yml[h->data_len] = '\0';
      continue;
    }

    int rows = 0, cols = 0;
    if (!collapse_shape(shapes[i], h->shape_len, &rows, &cols)) {
      set_err(err, errsz, "invalid tensor shape in model file");
      goto fail;
    }
    uint64_t n = (uint64_t)rows * (uint64_t)cols;

    if (h->type == SK_TYPE_FLOAT32) {
      if (!payload_matches(data, h->data_len, n * 4)) {
        set_err(err, errsz, "float tensor payload has the wrong size");
        goto fail;
      }
      t->data = malloc(n * sizeof(float));
      if (!t->data) goto fail_oom;
      memcpy(t->data, data, n * sizeof(float));
      for (uint64_t value = 0; value < n; value++) {
        if (!isfinite(t->data[value])) {
          set_err(err, errsz, "float tensor contains a non-finite value");
          goto fail;
        }
      }
      t->rows = rows;
      t->cols = cols;
    } else if (h->type == SK_TYPE_INTGEMM8) {
      if (!payload_matches(data, h->data_len, n + 4)) {
        set_err(err, errsz, "quantized tensor payload has the wrong size");
        goto fail;
      }
      float quant_mult;
      memcpy(&quant_mult, data + n, sizeof(float));
      if (!(quant_mult > 0.0f) || !isfinite(quant_mult)) {
        set_err(err, errsz, "invalid quantization multiplier in model file");
        goto fail;
      }
      t->qdata = malloc(n);
      if (!t->qdata) goto fail_oom;
      memcpy(t->qdata, data, n);
      t->qscale = quant_mult;
      /* Gemm weights are stored transposed on disk (except Wemb): record the
       * stored layout dims so consumers read the memory as it is. */
      if (is_wemb_name(t->name) || rows == 1 || cols == 1) {
        t->rows = rows;
        t->cols = cols;
      } else {
        t->rows = cols;
        t->cols = rows;
      }
    } else {
      /* Unknown tensor type: keep the name, drop the payload. */
      t->rows = rows;
      t->cols = cols;
    }
  }

  if (!mf->config_yml) {
    set_err(err, errsz, "model file has no embedded config (special:model.yml)");
    goto fail;
  }
  free(headers);
  free(buf);
  return mf;

fail_truncated:
  set_err(err, errsz, "model file is truncated or corrupt");
fail:
  free(headers);
  free(buf);
  sk_model_file_free(mf);
  return NULL;
fail_oom:
  set_err(err, errsz, "out of memory loading model");
  free(headers);
  free(buf);
  sk_model_file_free(mf);
  return NULL;
#undef NEED
}

void sk_model_file_free(sk_model_file *mf) {
  if (!mf) return;
  if (mf->tensors) {
    for (int i = 0; i < mf->count; i++) {
      free(mf->tensors[i].name);
      free(mf->tensors[i].data);
      free(mf->tensors[i].qdata);
    }
    free(mf->tensors);
  }
  free(mf->config_yml);
  free(mf);
}

const sk_tensor *sk_model_file_find(const sk_model_file *mf, const char *name) {
  for (int i = 0; i < mf->count; i++) {
    if (strcmp(mf->tensors[i].name, name) == 0) return &mf->tensors[i];
  }
  return NULL;
}
