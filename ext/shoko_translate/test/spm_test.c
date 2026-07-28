#define _POSIX_C_SOURCE 200809L

#include "spm.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define PIECE_NORMAL 1
#define PIECE_UNKNOWN 2
#define PIECE_CONTROL 3
#define PIECE_BYTE 6

static int failures;

static void check(int condition, const char *message) {
  if (condition) return;
  fprintf(stderr, "spm_test: %s\n", message);
  failures++;
}

static void write_varint(FILE *file, uint64_t value) {
  do {
    unsigned char byte = (unsigned char)(value & 0x7fu);
    value >>= 7;
    if (value) byte |= 0x80u;
    fputc(byte, file);
  } while (value);
}

static size_t varint_size(uint64_t value) {
  size_t size = 1;
  while (value >>= 7) size++;
  return size;
}

static void write_piece(FILE *file, const char *text, float score, int type) {
  size_t length = strlen(text);
  size_t message_size = 1 + varint_size(length) + length + 1 + 4 + 1 +
                        varint_size((uint64_t)type);
  fputc(0x0a, file);
  write_varint(file, message_size);
  fputc(0x0a, file);
  write_varint(file, length);
  fwrite(text, 1, length, file);
  fputc(0x15, file);
  fwrite(&score, sizeof(score), 1, file);
  fputc(0x18, file);
  write_varint(file, (uint64_t)type);
}

static int make_vocab(char path[], int invalid_byte_piece) {
  int fd = mkstemp(path);
  if (fd < 0) return 0;
  FILE *file = fdopen(fd, "wb");
  if (!file) {
    close(fd);
    return 0;
  }

  write_piece(file, "<unk>", -10.0f, PIECE_UNKNOWN);
  write_piece(file, "<s>", 0.0f, PIECE_CONTROL);
  write_piece(file, "</s>", 0.0f, PIECE_CONTROL);
  write_piece(file, "\xe2\x96\x81", 1.0f, PIECE_NORMAL);
  write_piece(file, "\xe2\x96\x81hello", 10.0f, PIECE_NORMAL);
  if (invalid_byte_piece) {
    write_piece(file, "<bad>", 0.0f, PIECE_BYTE);
  } else {
    for (int value = 0; value < 256; value++) {
      char byte_piece[7];
      snprintf(byte_piece, sizeof(byte_piece), "<0x%02X>", value);
      write_piece(file, byte_piece, 0.0f, PIECE_BYTE);
    }
  }
  return fclose(file) == 0;
}

int main(void) {
  char path[] = "/tmp/shoko-spm-test-XXXXXX";
  check(make_vocab(path, 0), "could not create test vocabulary");

  char error[256] = {0};
  sk_vocab *vocab = sk_vocab_load(path, error, sizeof(error));
  unlink(path);
  check(vocab != NULL, error[0] ? error : "valid vocabulary was rejected");
  if (!vocab) return 1;
  check(sk_vocab_size(vocab) == 261, "unexpected vocabulary size");

  int ids[16];
  int count = sk_vocab_encode(vocab, "hello", ids, 16);
  check(count == 1 && ids[0] == 4, "normal piece did not win Viterbi scoring");
  char *decoded = sk_vocab_decode(vocab, ids, count);
  check(decoded && strcmp(decoded, "hello") == 0, "normal piece round-trip failed");
  free(decoded);

  count = sk_vocab_encode(vocab, "\xc3\xa9", ids, 16);
  check(count == 3, "unknown codepoint was not expanded to byte pieces");
  decoded = sk_vocab_decode(vocab, ids, count);
  check(decoded && strcmp(decoded, "\xc3\xa9") == 0, "byte fallback round-trip failed");
  free(decoded);

  int unknown[] = {0};
  decoded = sk_vocab_decode(vocab, unknown, 1);
  check(decoded && strcmp(decoded, "\xef\xbf\xbd") == 0,
        "unknown piece was silently discarded");
  free(decoded);
  sk_vocab_free(vocab);

  char invalid_path[] = "/tmp/shoko-spm-invalid-XXXXXX";
  check(make_vocab(invalid_path, 1), "could not create invalid vocabulary");
  vocab = sk_vocab_load(invalid_path, error, sizeof(error));
  unlink(invalid_path);
  check(vocab == NULL, "malformed byte piece was accepted");
  sk_vocab_free(vocab);

  if (failures) return 1;
  puts("SentencePiece tests passed");
  return 0;
}
