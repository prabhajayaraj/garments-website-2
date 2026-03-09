
#!/bin/bash
set -e
echo "Building static HTML site..."
mkdir -p build
cp index.html build/
echo "Build complete. Output in /build"
