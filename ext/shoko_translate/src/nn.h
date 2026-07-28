/* Bergamot/Marian "student" transformer inference: N-layer encoder,
 * M-layer decoder with SSRU autoregression, tied embeddings, greedy search.
 * Architecture parameters come from the model file's embedded config. */
#ifndef SK_NN_H
#define SK_NN_H

#include <stddef.h>

#include "marian_bin.h"
#include "spm.h"

typedef struct sk_nn sk_nn;

/* Builds an inference model over a loaded file + vocab; takes ownership of
 * both on success. Returns NULL on failure and writes a message into err. */
sk_nn *sk_nn_create(sk_model_file *mf, sk_vocab *vocab, char *err,
                    size_t errsz);
void sk_nn_free(sk_nn *m);

/* Translates one sentence (UTF-8, pre-normalized). Returns a malloc'd
 * string, or NULL with a message in err. Sets truncated when decoding
 * exhausted its output budget without producing EOS. */
char *sk_nn_translate(sk_nn *m, const char *text, int *truncated,
                      char *err, size_t errsz);

#endif
