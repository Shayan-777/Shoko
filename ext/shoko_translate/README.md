# shoko-translate

Offline translation engine for Shoko's in-app translator. A single
dependency-free C11 program (libc + libm only) that runs the neural
translation models Mozilla ships for Firefox Translations — the
Bergamot/Marian "student" transformers — entirely on-device.

Shoko starts it as a child process and talks JSON-lines over
stdin/stdout. It is not meant to be used directly, but it can be:

```sh
make                       # portable build
make native                # adds -march=native for this machine
./shoko-translate <<'EOF'
{"op":"load","slot":"eten","model":"model.eten.intgemm.alphas.bin","vocab":"vocab.eten.spm"}
{"op":"translate","slot":"eten","text":"Tere!"}
EOF
```

## Protocol

One JSON object per line in, one per line out. Requests carry flat string
fields only.

| request | response |
|---|---|
| `{"op":"ping"}` | `{"ok":true,"version":"...","max_slots":4}` |
| `{"op":"load","slot":S,"model":PATH,"vocab":PATH}` | `{"ok":true}` (plus `evicted` when applicable) |
| `{"op":"translate","slot":S,"text":T}` | `{"ok":true,"text":T',"finish_reason":"eos"}` |
| `{"op":"unload","slot":S}` | `{"ok":true}` |

Errors come back as `{"ok":false,"code":"...","error":"..."}`; the process
never exits on bad input. Requests are strict UTF-8 JSON: unknown fields,
duplicate fields, non-string values, invalid escapes, and lines over 1 MiB
are rejected without changing engine state. Up to 4 models stay resident
(LRU-evicted). `text` must be a single sentence-ish segment,
NFKC-normalized, ≤ 16 KB — Shoko's adapter handles splitting and
normalization. A translation that exhausts its decoder budget reports
`"finish_reason":"max_tokens"`.

## Model format notes

The `.intgemm.alphas.bin` files are Marian binary models: int8-quantized
weights plus float32 biases/layer-norms, with the full architecture config
embedded in the file (`special:model.yml`). Two facts worth knowing because
they are documented nowhere outside the Marian source:

- each int8 tensor's dequantization scale is a float stored directly after
  its payload (`w = int8 / scale`), and tensor records may then be
  zero-padded to a 256-byte boundary,
- every gemm weight is stored **transposed** on disk — except `Wemb`
  (see `expression_graph_packable.h` in marian-dev: "Do not transpose the
  Wemb matrix. Hacky temporary solution").

The engine keeps the transposed layout and dot-products over contiguous
rows, so no transposition happens at load or run time.

Supported architecture (validated against the embedded config at load):
transformer encoder, SSRU decoder (`transformer-decoder-autoreg: rnn`),
tied embeddings, ReLU FFN, `dan` postprocess, sinusoidal positions.
That covers every "tiny" and "base" student Mozilla has published; the
dimensions (embedding, FFN, depths, heads) are read from the config, not
hardcoded. Decoding is greedy, which is deterministic — `test/golden.sh`
pins known-good translations.

## Testing

```sh
make test

# Optional real-model compatibility/golden test:
test/golden.sh /path/to/model.eten.intgemm.alphas.bin /path/to/vocab.eten.spm
```

`make test` covers the strict JSON-lines protocol, SentencePiece protobuf
loading/Viterbi/byte fallback, and Marian float/int8 tensor loading. The
optional golden test is deliberately separate because model files are not
stored in this repository.
