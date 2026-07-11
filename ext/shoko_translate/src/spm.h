/* Minimal SentencePiece unigram tokenizer: parses the pieces out of the
 * .spm protobuf and segments text with Viterbi search. Input text must
 * already be Unicode-normalized (Shoko does NFKC + whitespace collapse on
 * the Ruby side before it reaches the engine). */
#ifndef SK_SPM_H
#define SK_SPM_H

#include <stddef.h>

typedef struct sk_vocab sk_vocab;

/* Returns NULL on failure and writes a message into err. */
sk_vocab *sk_vocab_load(const char *path, char *err, size_t errsz);
void sk_vocab_free(sk_vocab *v);

int sk_vocab_size(const sk_vocab *v);

/* Encodes UTF-8 text into piece ids. Returns the id count, or -1 if the
 * text or the id budget is exceeded. */
int sk_vocab_encode(const sk_vocab *v, const char *text, int *ids, int max_ids);

/* Decodes ids back into UTF-8 text. Returns a malloc'd string. */
char *sk_vocab_decode(const sk_vocab *v, const int *ids, int count);

#endif
