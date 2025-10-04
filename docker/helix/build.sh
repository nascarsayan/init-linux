# Save as Dockerfile
docker build -t helix-glibc228 .

# Run interactively
docker run -it --rm helix-glibc228

# Export the binary to your host (optional)
docker cp "$(docker create helix-glibc228)":/usr/local/bin/hx ./hx
