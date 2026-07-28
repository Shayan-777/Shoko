#define _POSIX_C_SOURCE 200809L

#include "marian_bin.h"

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define TYPE_INTGEMM8 0x4101u
#define TYPE_FLOAT32 0x404u

typedef struct {
  const char *name;
  uint64_t type;
  uint64_t shape_len;
  uint64_t data_len;
  int32_t shape[2];
} test_tensor;

static int failures;

static void check(int condition, const char *message) {
  if (condition) return;
  fprintf(stderr, "marian_bin_test: %s\n", message);
  failures++;
}

static void write_u64(FILE *file, uint64_t value) {
  fwrite(&value, sizeof(value), 1, file);
}

static uint64_t stored_size(uint64_t payload, int padded) {
  return padded ? (payload + 255) & ~UINT64_C(255) : payload;
}

static void write_zero_padding(FILE *file, uint64_t payload, uint64_t stored) {
  for (uint64_t i = payload; i < stored; i++) fputc(0, file);
}

static int make_model(char path[], float quant_scale, int padded) {
  int fd = mkstemp(path);
  if (fd < 0) return 0;
  FILE *file = fdopen(fd, "wb");
  if (!file) {
    close(fd);
    return 0;
  }

  const char config[] = "type: transformer\n";
  const float values[] = {1.25f, -2.5f};
  const int8_t quantized[] = {1, -2, 3, -4, 5, -6};
  test_tensor tensors[] = {
    {"special:model.yml", 0, 0, sizeof(config) - 1, {0, 0}},
    {"float", TYPE_FLOAT32, 2, 0, {1, 2}},
    {"weight", TYPE_INTGEMM8, 2, 0, {2, 3}},
  };
  tensors[1].data_len = stored_size(sizeof(values), padded);
  tensors[2].data_len =
    stored_size(sizeof(quantized) + sizeof(float), padded);

  write_u64(file, 1);
  write_u64(file, 3);
  for (size_t i = 0; i < 3; i++) {
    write_u64(file, strlen(tensors[i].name) + 1);
    write_u64(file, tensors[i].type);
    write_u64(file, tensors[i].shape_len);
    write_u64(file, tensors[i].data_len);
  }
  for (size_t i = 0; i < 3; i++)
    fwrite(tensors[i].name, 1, strlen(tensors[i].name) + 1, file);
  for (size_t i = 0; i < 3; i++)
    fwrite(tensors[i].shape, sizeof(int32_t), tensors[i].shape_len, file);
  write_u64(file, 0);
  fwrite(config, 1, sizeof(config) - 1, file);
  fwrite(values, sizeof(float), 2, file);
  write_zero_padding(file, sizeof(values), tensors[1].data_len);
  fwrite(quantized, sizeof(int8_t), 6, file);
  fwrite(&quant_scale, sizeof(float), 1, file);
  write_zero_padding(
    file, sizeof(quantized) + sizeof(float), tensors[2].data_len
  );
  return fclose(file) == 0;
}

int main(void) {
  char path[] = "/tmp/shoko-marian-test-XXXXXX";
  check(make_model(path, 8.0f, 1), "could not create test model");
  char error[256] = {0};
  sk_model_file *model = sk_model_file_load(path, error, sizeof(error));
  unlink(path);
  check(model != NULL, error[0] ? error : "valid model was rejected");
  if (!model) return 1;

  const sk_tensor *plain = sk_model_file_find(model, "float");
  check(plain && plain->data && !plain->qdata, "float tensor payload was not retained");
  check(plain && plain->rows == 1 && plain->cols == 2, "float tensor shape changed");
  check(plain && plain->data[0] == 1.25f && plain->data[1] == -2.5f,
        "float tensor values changed");

  const sk_tensor *quantized = sk_model_file_find(model, "weight");
  check(quantized && quantized->qdata && !quantized->data,
        "quantized tensor was eagerly expanded");
  check(quantized && quantized->rows == 3 && quantized->cols == 2,
        "quantized GEMM layout was not transposed");
  check(quantized && quantized->qscale == 8.0f && quantized->qdata[1] == -2,
        "quantized tensor metadata changed");
  sk_model_file_free(model);

  char invalid_path[] = "/tmp/shoko-marian-invalid-XXXXXX";
  check(make_model(invalid_path, INFINITY, 1), "could not create invalid model");
  model = sk_model_file_load(invalid_path, error, sizeof(error));
  unlink(invalid_path);
  check(model == NULL, "non-finite quantization scale was accepted");
  sk_model_file_free(model);

  if (failures) return 1;
  puts("Marian binary tests passed");
  return 0;
}
