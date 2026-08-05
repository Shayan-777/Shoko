# External book fixtures

Real-book regression inputs are release assets, not Git content. CI downloads
`book-fixtures-v1.tar.gz` and `SHA256SUMS` from the `book-fixtures-v1` release,
verifies the archive, and extracts it under `tmp/book-fixtures`.

For local runs, download the same two assets from the project's GitHub mirror
release page and verify before extracting:

```bash
mkdir -p tmp/book-fixtures
curl --fail --location RELEASE_URL/book-fixtures-v1.tar.gz --output tmp/book-fixtures-v1.tar.gz
curl --fail --location RELEASE_URL/SHA256SUMS --output tmp/SHA256SUMS
(cd tmp && grep 'book-fixtures-v1.tar.gz' SHA256SUMS | sha256sum --check --strict)
tar -xzf tmp/book-fixtures-v1.tar.gz -C tmp/book-fixtures --strip-components=1
SHOKO_BOOK_FIXTURES=1 bundle exec rake test:fixtures
```

Replace `RELEASE_URL` with the full
`https://github.com/OWNER/REPOSITORY/releases/download/book-fixtures-v1` URL.
Use `SHOKO_FIXTURES_DIR=/absolute/path` when the corpus is extracted elsewhere.

The test lane checks for these baseline files before it starts:

- `Pride and Prejudice (Jane Austen).mobi`
- `Pride Prejudice (Jane Austen).azw`
- `Pride and Prejudice (Jane Austen).azw3`
- `Pride And Prejudice (Austen Jane).rtf`
- `The Invention of Hugo Cabret (Selznick Brian).azw3`
- `The Decline of the West An Abridged Edition (Oswald Spengler) (an abridged edition)).pdf`
- `class struggle A Political and Philosophical History (Domenico Losurdo).pdf`

The release may contain additional formats used by tagged regression and
performance cases. Updating the corpus requires a new versioned release and
checksum; never add book binaries back to the repository.
