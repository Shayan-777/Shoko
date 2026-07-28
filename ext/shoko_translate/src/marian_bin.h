/* Loader for Marian binary model files (the format Mozilla distributes for
 * Firefox Translations). Parses the header, dequantizes intgemm8 tensors to
 * float32 and exposes tensors by name.
 *
 * Layout facts this loader relies on (verified against marian-dev source and
 * live model files):
 *   - file: u64 version(=1), u64 count, count * {u64 name_len, u64 type,
 *     u64 shape_len, u64 data_len}, names (NUL included in name_len),
 *     i32 shapes, u64 pad_len, pad, then data blocks in header order.
 *   - intgemm8 (0x4101): int8 payload followed by the weight quantMult as a
 *     float at byte offset prod(shape); dequant is int8 / quantMult.
 *   - every intgemm8 gemm weight is stored TRANSPOSED on disk except Wemb
 *     (marian expression_graph_packable.h). We keep the on-disk layout and
 *     record the stored row/col dims, so gemm consumes it directly.
 */
#ifndef SK_MARIAN_BIN_H
#define SK_MARIAN_BIN_H

#include <stddef.h>
#include <stdint.h>

typedef struct {
  char *name;
  float *data;    /* float32 payload, row-major in STORED layout */
  int8_t *qdata;  /* int8 payload when quantized */
  float qscale;   /* real value = qdata / qscale */
  int rows;     /* stored leading dim */
  int cols;     /* stored trailing dim */
} sk_tensor;

typedef struct {
  sk_tensor *tensors;
  int count;
  char *config_yml; /* contents of special:model.yml, NUL-terminated */
} sk_model_file;

/* Returns NULL on failure and writes a message into err. */
sk_model_file *sk_model_file_load(const char *path, char *err, size_t errsz);
void sk_model_file_free(sk_model_file *mf);
const sk_tensor *sk_model_file_find(const sk_model_file *mf, const char *name);

#endif
