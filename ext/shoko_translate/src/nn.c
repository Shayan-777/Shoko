#define _POSIX_C_SOURCE 200809L

#include "nn.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SK_MAX_LAYERS 12
#define SK_MAX_SRC_TOKENS 512
#define SK_MAX_OUT_TOKENS 768
#define SK_EOS_ID 0
#define SK_LN_EPS 1e-9f

/* rows x cols row-major matrix view over loaded tensor data. Gemm weights
 * keep their on-disk transposed layout: rows = output dim, cols = input dim,
 * so y = x @ W + b becomes per-output-row dot products over contiguous
 * memory (see marian_bin.h). */
typedef struct {
  const float *d;
  int rows;
  int cols;
} sk_mat;

typedef struct {
  sk_mat Wq, Wk, Wv, Wo;
  const float *bq, *bk, *bv, *bo;
  const float *ln_scale, *ln_bias;
} sk_attn_params;

typedef struct {
  sk_mat W1, W2;
  const float *b1, *b2;
  const float *ln_scale, *ln_bias;
} sk_ffn_params;

typedef struct {
  sk_attn_params self;
  sk_ffn_params ffn;
} sk_enc_layer;

typedef struct {
  sk_mat rnn_W, rnn_Wf;
  const float *rnn_bf;
  const float *rnn_ln_scale, *rnn_ln_bias;
  sk_attn_params context;
  sk_ffn_params ffn;
} sk_dec_layer;

struct sk_nn {
  sk_model_file *file;
  sk_vocab *vocab;
  int dim, heads, head_dim, ffn_dim, enc_depth, dec_depth, vocab_size;
  float emb_scale;
  sk_mat wemb; /* vocab_size x dim, plain row-major */
  const float *logit_bias;
  sk_enc_layer enc[SK_MAX_LAYERS];
  sk_dec_layer dec[SK_MAX_LAYERS];
};

static void set_err(char *err, size_t errsz, const char *msg) {
  if (err && errsz) snprintf(err, errsz, "%s", msg);
}

/* --- embedded config --------------------------------------------------- */

/* The embedded config is flat "key: value" YAML; list values are irrelevant
 * to the keys we read. */
static int config_str(const char *yml, const char *key, char *out,
                      size_t outsz) {
  size_t klen = strlen(key);
  const char *p = yml;
  while (p && *p) {
    if (strncmp(p, key, klen) == 0 && p[klen] == ':') {
      const char *v = p + klen + 1;
      while (*v == ' ') v++;
      size_t n = strcspn(v, "\r\n");
      if (n >= outsz) n = outsz - 1;
      memcpy(out, v, n);
      out[n] = '\0';
      return 1;
    }
    p = strchr(p, '\n');
    if (p) p++;
  }
  return 0;
}

static int config_int(const char *yml, const char *key, int *out) {
  char buf[64];
  if (!config_str(yml, key, buf, sizeof(buf))) return 0;
  *out = atoi(buf);
  return *out > 0;
}

static int config_equals(const char *yml, const char *key,
                         const char *expected) {
  char buf[64];
  return config_str(yml, key, buf, sizeof(buf)) &&
         strcmp(buf, expected) == 0;
}

/* --- primitives --------------------------------------------------------- */

/* C[m x n] = A[m x k] . Wt[n x k]^T (+ bias[n] when given) */
static void gemm_bt(const float *restrict a, const sk_mat *wt,
                    float *restrict c, int m, const float *restrict bias) {
  int k = wt->cols, n = wt->rows;
  for (int i = 0; i < m; i++) {
    const float *ai = a + (size_t)i * k;
    float *ci = c + (size_t)i * n;
    for (int j = 0; j < n; j++) {
      const float *bj = wt->d + (size_t)j * k;
      float acc = 0.0f;
      for (int x = 0; x < k; x++) acc += ai[x] * bj[x];
      ci[j] = bias ? acc + bias[j] : acc;
    }
  }
}

static void layer_norm(float *x, int m, int dim, const float *scale,
                       const float *bias) {
  for (int i = 0; i < m; i++) {
    float *row = x + (size_t)i * dim;
    float mean = 0.0f;
    for (int j = 0; j < dim; j++) mean += row[j];
    mean /= dim;
    float var = 0.0f;
    for (int j = 0; j < dim; j++) {
      float e = row[j] - mean;
      var += e * e;
    }
    var /= dim;
    float inv = 1.0f / sqrtf(var + SK_LN_EPS);
    for (int j = 0; j < dim; j++)
      row[j] = (row[j] - mean) * inv * scale[j] + bias[j];
  }
}

static void softmax_inplace(float *x, int n) {
  float mx = x[0];
  for (int i = 1; i < n; i++)
    if (x[i] > mx) mx = x[i];
  float sum = 0.0f;
  for (int i = 0; i < n; i++) {
    x[i] = expf(x[i] - mx);
    sum += x[i];
  }
  float inv = 1.0f / sum;
  for (int i = 0; i < n; i++) x[i] *= inv;
}

/* marian/tensor2tensor sinusoidal positions: first half sines, second half
 * cosines, timescale exponent i/(dim/2 - 1). */
static void positional_embedding(int pos, int dim, float *out) {
  int half = dim / 2;
  float log_inc = logf(10000.0f) / (float)(half - 1);
  for (int i = 0; i < half; i++) {
    float v = (float)pos * expf(-log_inc * (float)i);
    out[i] = sinf(v);
    out[half + i] = cosf(v);
  }
}

static void embed_token(const sk_nn *m, int id, int pos, float *out) {
  const float *row = m->wemb.d + (size_t)id * m->dim;
  float pe[1024];
  positional_embedding(pos, m->dim, pe);
  for (int j = 0; j < m->dim; j++) out[j] = row[j] * m->emb_scale + pe[j];
}

/* Multi-head attention: q_in (lq x dim) attends over precomputed K/V
 * (lk x dim each; already projected). Writes lq x dim into out. */
static void attend(const sk_nn *m, const sk_attn_params *p,
                   const float *q_in, int lq, const float *k, const float *v,
                   int lk, float *out, float *scratch) {
  int dim = m->dim, hd = m->head_dim;
  float *q = scratch;                 /* lq x dim */
  float *scores = q + (size_t)lq * dim; /* lk */
  float *ctx = scores + lk;             /* lq x dim */
  float inv_sqrt = 1.0f / sqrtf((float)hd);

  gemm_bt(q_in, &p->Wq, q, lq, p->bq);
  for (int i = 0; i < lq; i++) {
    const float *qi = q + (size_t)i * dim;
    float *ci = ctx + (size_t)i * dim;
    for (int h = 0; h < m->heads; h++) {
      const float *qh = qi + h * hd;
      for (int j = 0; j < lk; j++) {
        const float *kh = k + (size_t)j * dim + h * hd;
        float acc = 0.0f;
        for (int x = 0; x < hd; x++) acc += qh[x] * kh[x];
        scores[j] = acc * inv_sqrt;
      }
      softmax_inplace(scores, lk);
      float *ch = ci + h * hd;
      for (int x = 0; x < hd; x++) ch[x] = 0.0f;
      for (int j = 0; j < lk; j++) {
        const float *vh = v + (size_t)j * dim + h * hd;
        float w = scores[j];
        for (int x = 0; x < hd; x++) ch[x] += w * vh[x];
      }
    }
  }
  gemm_bt(ctx, &p->Wo, out, lq, p->bo);
}

/* residual add + layer norm ("dan" postprocess) */
static void add_norm(float *x, const float *residual, int m_rows, int dim,
                     const float *scale, const float *bias) {
  for (int i = 0; i < m_rows * dim; i++) x[i] += residual[i];
  layer_norm(x, m_rows, dim, scale, bias);
}

static void ffn_block(const sk_nn *m, const sk_ffn_params *p, float *x,
                      int rows, float *scratch) {
  float *h1 = scratch;                      /* rows x ffn_dim */
  float *h2 = h1 + (size_t)rows * m->ffn_dim; /* rows x dim */
  gemm_bt(x, &p->W1, h1, rows, p->b1);
  for (int i = 0; i < rows * m->ffn_dim; i++)
    if (h1[i] < 0.0f) h1[i] = 0.0f;
  gemm_bt(h1, &p->W2, h2, rows, p->b2);
  add_norm(h2, x, rows, m->dim, p->ln_scale, p->ln_bias);
  memcpy(x, h2, (size_t)rows * m->dim * sizeof(float));
}

/* --- wiring ------------------------------------------------------------- */

static const sk_tensor *need(const sk_model_file *mf, const char *fmt,
                             const char *prefix, char *err, size_t errsz) {
  char name[128];
  snprintf(name, sizeof(name), fmt, prefix);
  const sk_tensor *t = sk_model_file_find(mf, name);
  if (!t || !t->data) {
    char msg[192];
    snprintf(msg, sizeof(msg), "model tensor missing: %s", name);
    set_err(err, errsz, msg);
    return NULL;
  }
  return t;
}

static int wire_mat(const sk_model_file *mf, const char *fmt,
                    const char *prefix, sk_mat *out, char *err,
                    size_t errsz) {
  const sk_tensor *t = need(mf, fmt, prefix, err, errsz);
  if (!t) return 0;
  out->d = t->data;
  out->rows = t->rows;
  out->cols = t->cols;
  return 1;
}

static int wire_vec(const sk_model_file *mf, const char *fmt,
                    const char *prefix, const float **out, char *err,
                    size_t errsz) {
  const sk_tensor *t = need(mf, fmt, prefix, err, errsz);
  if (!t) return 0;
  *out = t->data;
  return 1;
}

static int wire_attn(const sk_model_file *mf, const char *prefix,
                     sk_attn_params *p, char *err, size_t errsz) {
  return wire_mat(mf, "%s_Wq", prefix, &p->Wq, err, errsz) &&
         wire_mat(mf, "%s_Wk", prefix, &p->Wk, err, errsz) &&
         wire_mat(mf, "%s_Wv", prefix, &p->Wv, err, errsz) &&
         wire_mat(mf, "%s_Wo", prefix, &p->Wo, err, errsz) &&
         wire_vec(mf, "%s_bq", prefix, &p->bq, err, errsz) &&
         wire_vec(mf, "%s_bk", prefix, &p->bk, err, errsz) &&
         wire_vec(mf, "%s_bv", prefix, &p->bv, err, errsz) &&
         wire_vec(mf, "%s_bo", prefix, &p->bo, err, errsz) &&
         wire_vec(mf, "%s_Wo_ln_scale", prefix, &p->ln_scale, err, errsz) &&
         wire_vec(mf, "%s_Wo_ln_bias", prefix, &p->ln_bias, err, errsz);
}

static int wire_ffn(const sk_model_file *mf, const char *prefix,
                    sk_ffn_params *p, char *err, size_t errsz) {
  return wire_mat(mf, "%s_W1", prefix, &p->W1, err, errsz) &&
         wire_mat(mf, "%s_W2", prefix, &p->W2, err, errsz) &&
         wire_vec(mf, "%s_b1", prefix, &p->b1, err, errsz) &&
         wire_vec(mf, "%s_b2", prefix, &p->b2, err, errsz) &&
         wire_vec(mf, "%s_ffn_ln_scale", prefix, &p->ln_scale, err, errsz) &&
         wire_vec(mf, "%s_ffn_ln_bias", prefix, &p->ln_bias, err, errsz);
}

sk_nn *sk_nn_create(sk_model_file *mf, sk_vocab *vocab, char *err,
                    size_t errsz) {
  const char *yml = mf->config_yml;
  if (!config_equals(yml, "type", "transformer") ||
      !config_equals(yml, "transformer-decoder-autoreg", "rnn") ||
      !config_equals(yml, "dec-cell", "ssru") ||
      !config_equals(yml, "tied-embeddings-all", "true") ||
      !config_equals(yml, "transformer-ffn-activation", "relu") ||
      !config_equals(yml, "transformer-postprocess", "dan")) {
    set_err(err, errsz, "unsupported model architecture (expected a tied-embedding SSRU transformer student)");
    return NULL;
  }

  sk_nn *m = calloc(1, sizeof(*m));
  if (!m) {
    set_err(err, errsz, "out of memory");
    return NULL;
  }
  if (!config_int(yml, "dim-emb", &m->dim) ||
      !config_int(yml, "enc-depth", &m->enc_depth) ||
      !config_int(yml, "dec-depth", &m->dec_depth) ||
      !config_int(yml, "transformer-heads", &m->heads) ||
      !config_int(yml, "transformer-dim-ffn", &m->ffn_dim)) {
    set_err(err, errsz, "model config is missing required dimensions");
    free(m);
    return NULL;
  }
  if (m->dim > 1024 || m->dim % 2 != 0 || m->heads <= 0 ||
      m->dim % m->heads != 0 || m->enc_depth > SK_MAX_LAYERS ||
      m->dec_depth > SK_MAX_LAYERS) {
    set_err(err, errsz, "model dimensions out of supported range");
    free(m);
    return NULL;
  }
  m->head_dim = m->dim / m->heads;
  m->emb_scale = sqrtf((float)m->dim);

  const sk_tensor *wemb = sk_model_file_find(mf, "Wemb");
  const sk_tensor *lbias = sk_model_file_find(mf, "decoder_ff_logit_out_b");
  if (!wemb || !wemb->data || !lbias || !lbias->data ||
      wemb->cols != m->dim) {
    set_err(err, errsz, "model embeddings are missing or malformed");
    free(m);
    return NULL;
  }
  m->wemb = (sk_mat){wemb->data, wemb->rows, wemb->cols};
  m->logit_bias = lbias->data;
  m->vocab_size = wemb->rows;
  if (sk_vocab_size(vocab) != m->vocab_size) {
    set_err(err, errsz, "vocabulary size does not match the model");
    free(m);
    return NULL;
  }

  char prefix[64];
  for (int l = 1; l <= m->enc_depth; l++) {
    snprintf(prefix, sizeof(prefix), "encoder_l%d_self", l);
    if (!wire_attn(mf, prefix, &m->enc[l - 1].self, err, errsz)) goto fail;
    snprintf(prefix, sizeof(prefix), "encoder_l%d_ffn", l);
    if (!wire_ffn(mf, prefix, &m->enc[l - 1].ffn, err, errsz)) goto fail;
  }
  for (int l = 1; l <= m->dec_depth; l++) {
    sk_dec_layer *d = &m->dec[l - 1];
    const sk_tensor *t;
    snprintf(prefix, sizeof(prefix), "decoder_l%d_rnn", l);
    if (!(t = need(mf, "%s_W", prefix, err, errsz))) goto fail;
    d->rnn_W = (sk_mat){t->data, t->rows, t->cols};
    if (!(t = need(mf, "%s_Wf", prefix, err, errsz))) goto fail;
    d->rnn_Wf = (sk_mat){t->data, t->rows, t->cols};
    if (!(t = need(mf, "%s_bf", prefix, err, errsz))) goto fail;
    d->rnn_bf = t->data;
    if (!(t = need(mf, "%s_ffn_ln_scale", prefix, err, errsz))) goto fail;
    d->rnn_ln_scale = t->data;
    if (!(t = need(mf, "%s_ffn_ln_bias", prefix, err, errsz))) goto fail;
    d->rnn_ln_bias = t->data;
    snprintf(prefix, sizeof(prefix), "decoder_l%d_context", l);
    if (!wire_attn(mf, prefix, &d->context, err, errsz)) goto fail;
    snprintf(prefix, sizeof(prefix), "decoder_l%d_ffn", l);
    if (!wire_ffn(mf, prefix, &d->ffn, err, errsz)) goto fail;
  }

  m->file = mf;
  m->vocab = vocab;
  return m;

fail:
  free(m);
  return NULL;
}

void sk_nn_free(sk_nn *m) {
  if (!m) return;
  sk_model_file_free(m->file);
  sk_vocab_free(m->vocab);
  free(m);
}

/* --- inference ---------------------------------------------------------- */

/* Encoder over n source ids; returns malloc'd n x dim. */
static float *encode(const sk_nn *m, const int *ids, int n) {
  int dim = m->dim;
  size_t row_bytes = (size_t)n * dim;
  float *x = malloc(row_bytes * sizeof(float));
  float *kbuf = malloc(row_bytes * sizeof(float));
  float *vbuf = malloc(row_bytes * sizeof(float));
  float *attn_out = malloc(row_bytes * sizeof(float));
  size_t scratch_elems =
      row_bytes + n + row_bytes + (size_t)n * m->ffn_dim + row_bytes;
  float *scratch = malloc(scratch_elems * sizeof(float));
  if (!x || !kbuf || !vbuf || !attn_out || !scratch) goto fail;

  for (int i = 0; i < n; i++) embed_token(m, ids[i], i, x + (size_t)i * dim);

  for (int l = 0; l < m->enc_depth; l++) {
    const sk_attn_params *p = &m->enc[l].self;
    gemm_bt(x, &p->Wk, kbuf, n, p->bk);
    gemm_bt(x, &p->Wv, vbuf, n, p->bv);
    attend(m, p, x, n, kbuf, vbuf, n, attn_out, scratch);
    add_norm(attn_out, x, n, dim, p->ln_scale, p->ln_bias);
    memcpy(x, attn_out, row_bytes * sizeof(float));
    ffn_block(m, &m->enc[l].ffn, x, n, scratch);
  }

  free(kbuf);
  free(vbuf);
  free(attn_out);
  free(scratch);
  return x;

fail:
  free(x);
  free(kbuf);
  free(vbuf);
  free(attn_out);
  free(scratch);
  return NULL;
}

static int greedy_decode(const sk_nn *m, const float *enc_out, int n_src,
                         int *out_ids, int max_out) {
  int dim = m->dim, count = -1;
  size_t src_bytes = (size_t)n_src * dim * sizeof(float);
  int layers = m->dec_depth;

  /* cross-attention K/V per decoder layer, projected once */
  float *k[SK_MAX_LAYERS] = {0}, *v[SK_MAX_LAYERS] = {0};
  float *cell = calloc((size_t)layers * dim, sizeof(float));
  float *x = malloc(dim * sizeof(float));
  float *h = malloc(dim * sizeof(float));
  float *tmp = malloc(dim * sizeof(float));
  float *xw = malloc(dim * sizeof(float));
  float *logits = malloc((size_t)m->vocab_size * sizeof(float));
  size_t scratch_elems = (size_t)dim + n_src + dim + (size_t)m->ffn_dim + dim;
  float *scratch = malloc(scratch_elems * sizeof(float));
  if (!cell || !x || !h || !tmp || !xw || !logits || !scratch) goto done;
  for (int l = 0; l < layers; l++) {
    k[l] = malloc(src_bytes);
    v[l] = malloc(src_bytes);
    if (!k[l] || !v[l]) goto done;
    gemm_bt(enc_out, &m->dec[l].context.Wk, k[l], n_src, m->dec[l].context.bk);
    gemm_bt(enc_out, &m->dec[l].context.Wv, v[l], n_src, m->dec[l].context.bv);
  }

  /* step 0: zero embedding (shifted target) + positional signal */
  positional_embedding(0, dim, x);
  count = 0;
  for (int step = 0; step < max_out; step++) {
    memcpy(h, x, dim * sizeof(float));
    for (int l = 0; l < layers; l++) {
      const sk_dec_layer *d = &m->dec[l];
      /* SSRU: c = f*c + (1-f)*(x@W); out = relu(c); then add+norm */
      gemm_bt(h, &d->rnn_W, xw, 1, NULL);
      gemm_bt(h, &d->rnn_Wf, tmp, 1, d->rnn_bf);
      float *c = cell + (size_t)l * dim;
      for (int j = 0; j < dim; j++) {
        float f = 1.0f / (1.0f + expf(-tmp[j]));
        c[j] = f * c[j] + (1.0f - f) * xw[j];
        tmp[j] = c[j] > 0.0f ? c[j] : 0.0f;
      }
      add_norm(tmp, h, 1, dim, d->rnn_ln_scale, d->rnn_ln_bias);
      memcpy(h, tmp, dim * sizeof(float));
      /* cross-attention over the encoder states */
      attend(m, &d->context, h, 1, k[l], v[l], n_src, tmp, scratch);
      add_norm(tmp, h, 1, dim, d->context.ln_scale, d->context.ln_bias);
      memcpy(h, tmp, dim * sizeof(float));
      ffn_block(m, &d->ffn, h, 1, scratch);
    }
    gemm_bt(h, &m->wemb, logits, 1, m->logit_bias);
    int best = 0;
    float best_score = logits[0];
    for (int j = 1; j < m->vocab_size; j++) {
      if (logits[j] > best_score) {
        best_score = logits[j];
        best = j;
      }
    }
    if (best == SK_EOS_ID) break;
    out_ids[count++] = best;
    embed_token(m, best, step + 1, x);
  }

done:
  for (int l = 0; l < layers; l++) {
    free(k[l]);
    free(v[l]);
  }
  free(cell);
  free(x);
  free(h);
  free(tmp);
  free(xw);
  free(logits);
  free(scratch);
  return count;
}

char *sk_nn_translate(sk_nn *m, const char *text, char *err, size_t errsz) {
  int ids[SK_MAX_SRC_TOKENS];
  int n = sk_vocab_encode(m->vocab, text, ids, SK_MAX_SRC_TOKENS - 1);
  if (n < 0) {
    set_err(err, errsz, "text is too long for a single translation request");
    return NULL;
  }
  if (n == 0) return strdup("");
  ids[n++] = SK_EOS_ID;

  float *enc_out = encode(m, ids, n);
  if (!enc_out) {
    set_err(err, errsz, "out of memory during encoding");
    return NULL;
  }

  int out_ids[SK_MAX_OUT_TOKENS];
  int budget = 3 * n + 12;
  if (budget > SK_MAX_OUT_TOKENS) budget = SK_MAX_OUT_TOKENS;
  int out_n = greedy_decode(m, enc_out, n, out_ids, budget);
  free(enc_out);
  if (out_n < 0) {
    set_err(err, errsz, "out of memory during decoding");
    return NULL;
  }

  char *result = sk_vocab_decode(m->vocab, out_ids, out_n);
  if (!result) set_err(err, errsz, "out of memory during detokenization");
  return result;
}
