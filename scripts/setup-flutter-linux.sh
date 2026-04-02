#!/bin/bash
# Setup Flutter and Linux Desktop development dependencies on Fedora 43.
# Author: Junie

set -e

echo "--- Flutter Linux Desktop Setup ---"

# 1. Dependency Check (Fedora)
# These usually require sudo access.
echo "The following dependencies are required for Flutter Linux Desktop development on Fedora:"
echo "  dnf install clang cmake ninja-build pkg-config gtk3-devel xz-devel libstdc++-devel mesa-libGL-devel"
echo ""
echo "Attempting to verify presence of tools..."
MISSING_TOOLS=()
for tool in clang cmake ninja pkg-config; do
  if ! command -v $tool >/dev/null 2>&1; then
    MISSING_TOOLS+=($tool)
  fi
done

if [ ${#MISSING_TOOLS[@]} -ne 0 ]; then
  echo "WARNING: The following tools are missing: ${MISSING_TOOLS[*]}"
  echo "Please run the following command with sudo to install dependencies:"
  echo "  sudo dnf install clang cmake ninja-build pkgconf-pkg-config gtk3-devel xz-devel libstdc++-devel mesa-libGL-devel"
  # We can't proceed with 'flutter run -d linux' without these, but we can install Flutter SDK itself.
fi

# 2. Install Flutter SDK locally (if not present)
FLUTTER_DIR="$HOME/flutter"
if [ ! -d "$FLUTTER_DIR" ]; then
  echo "Cloning Flutter stable channel to $FLUTTER_DIR..."
  git clone https://github.com/flutter/flutter.git -b stable "$FLUTTER_DIR"
else
  echo "Flutter SDK already exists at $FLUTTER_DIR. Updating..."
  cd "$FLUTTER_DIR"
  git pull
  cd - > /dev/null
fi

# 3. Add to PATH for the current session
export PATH="$FLUTTER_DIR/bin:$PATH"

# 4. Configure Flutter
echo "Enabling Linux desktop support..."
flutter config --enable-linux-desktop

# 5. Verify installation
echo "Running flutter doctor..."
flutter doctor

echo ""
echo "--- Setup Complete ---"
echo "To use Flutter in future sessions, add the following to your ~/.bashrc:"
echo "  export PATH=\"$FLUTTER_DIR/bin:\$PATH\""
echo ""
echo "To run the RAG Explorer as a Linux app:"
echo "  cd rag-stack/services/rag-explorer"
echo "  flutter run -d linux"
