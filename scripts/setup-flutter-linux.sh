#!/bin/bash
# Setup Flutter and Linux Desktop development dependencies on Fedora 43.
# Author: Junie

set -e

echo "--- Flutter Linux Desktop Setup ---"

# 1. Dependency Check (Fedora)
# These usually require sudo access.
echo "The following dependencies are required for Flutter Linux Desktop development on Fedora:"
echo "  sudo dnf install -y clang cmake ninja-build pkgconf-pkg-config gtk3-devel xz-devel libstdc++-devel mesa-libGL-devel"
echo ""
echo "Attempting to install missing tools..."
sudo dnf install -y clang cmake ninja-build pkgconf-pkg-config gtk3-devel xz-devel libstdc++-devel mesa-libGL-devel

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

# 5. Verify and initialize projects
echo "Running flutter doctor..."
flutter doctor

echo ""
echo "Initializing RAG Explorer platform support..."
RAG_EXPLORER_DIR="rag-stack/services/rag-explorer"
if [ -d "$RAG_EXPLORER_DIR" ]; then
  cd "$RAG_EXPLORER_DIR"
  # Add linux and web support if missing
  "$FLUTTER_DIR/bin/flutter" create --platforms=linux,web .
  # Clean up any stale build artifacts that might cause permission issues (e.g. CMAKE_INSTALL_PREFIX)
  "$FLUTTER_DIR/bin/flutter" clean
  
  echo "Fetching dependencies and running code generation..."
  "$FLUTTER_DIR/bin/flutter" pub get
  "$FLUTTER_DIR/bin/flutter" pub run build_runner build --delete-conflicting-outputs
  
  cd - > /dev/null
fi

echo ""
echo "--- Setup Complete ---"
echo "To use Flutter in future sessions, add the following to your ~/.bashrc:"
echo "  export PATH=\"$FLUTTER_DIR/bin:\$PATH\""
echo ""
echo "To run the RAG Explorer as a Linux app:"
echo "  cd rag-stack/services/rag-explorer"
echo "  flutter run -d linux"
