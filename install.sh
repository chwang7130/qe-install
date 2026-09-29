#!/bin/bash

set -euo pipefail
set -x

QE_VERSION="${QE_VERSION:-7.6}"
QE_PREFIX="${QE_PREFIX:-$HOME/.local/quantum-espresso}"
DOWNLOAD_DIR="${TMPDIR:-/tmp}/qe-installer-$$"
TARBALL_NAME="q-e-qe-${QE_VERSION}.tar.gz"
DOWNLOAD_URL="https://gitlab.com/QEF/q-e/-/archive/qe-${QE_VERSION}/${TARBALL_NAME}"

# Refuse to run under sudo from a regular user's shell. This installer puts
# everything under $HOME, which under sudo typically resolves to root's home:
# the binary lands in /root/.local/bin (or is left root-owned in the user's
# home, depending on the distro's sudo configuration), and the 'qe'
# command is then not found in the user's own shell. Plain root with no sudo
# (containers, CI, root-only systems) is unaffected by this check.
if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ] && [ -z "${QE_INSTALL_ALLOW_SUDO:-}" ]; then
    echo "Error: do not run this installer with sudo." >&2
    echo "" >&2
    echo "QE installs into your current directory and does not need root access." >&2
    echo "With sudo, the installation would go into root's home directory instead of" >&2
    echo "yours." >&2
    echo "" >&2
    echo "Please re-run the same command without sudo, e.g.:" >&2
    # pinned-dep-allow: display-only guidance text in an error message, not an executed install; install.sh is Anthropic's own installer
    echo "    curl -fsSL https://qe.ai/install.sh | bash" >&2
    echo "" >&2
    echo "To intentionally install QE for the root user, re-run with" >&2
    echo "QE_INSTALL_ALLOW_SUDO=1 set in the installer's environment, e.g.:" >&2
    # pinned-dep-allow: display-only guidance text in an error message, not an executed install; install.sh is Anthropic's own installer
    echo "    curl -fsSL https://qe.ai/install.sh | sudo QE_INSTALL_ALLOW_SUDO=1 bash" >&2
    exit 1
fi

REQUIRED_TOOLS=("make" "tar")
MISSING_TOOLS=()
for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        MISSING_TOOLS+=("$tool")
    fi
done

if [ ${#MISSING_TOOLS[@]} -ne 0 ]; then
    echo "Missing necessary tool(s), please install them first: ${MISSING_TOOLS[*]}" >&2
    exit 1
fi

# Download function that works with both curl and wget
download_file() {
    local url="$1"
    local output="$2"
    
    if [ -n "$output" ]; then
        curl -fsSL -o "$output" "$url"
    else
        curl -fsSL "$url"
    fi
}

mkdir -p "$DOWNLOAD_DIR"

download_file "$DOWNLOAD_URL" "$DOWNLOAD_DIR/$TARBALL_NAME"

# Run qe install to set up launcher and shell integration
echo "Setting up Quantum Espresso..."
install_code=0

mkdir -p "$DOWNLOAD_DIR/src"
tar -xzf "$DOWNLOAD_DIR/$TARBALL_NAME" -C "$DOWNLOAD_DIR/src" --strip-components=1

module purge && module load gcc/10.4.0 openmpi/5.0.2

cd "$DOWNLOAD_DIR/src"
# ./configure --prefix="$QE_PREFIX"
# make -j4 pw

mkdir ./build
cd ./build
cmake -DCMAKE_Fortran_COMPILER=mpif90 \
    -DCMAKE_C_COMPILER=mpicc \
    -DCMAKE_INSTALL_PREFIX="$QE_PREFIX" \
    -DBLAS_LIBRARIES="-lblas" \
    -DLAPACK_LIBRARIES="-llapack" \
    -DQE_ENABLE_MPI=ON \
    -DQE_ENABLE_OPENMP=ON ..
make -j4 pw

mkdir -p "$QE_PREFIX/bin"
cp -r bin/* "$QE_PREFIX/bin/"

# Clean up downloaded file
rm -rf "$DOWNLOAD_DIR"

echo ""
echo "QE Installation complete!"
echo ""
echo "QE is installed at $QE_PREFIX/bin"
echo "Run the command below to permanently add qe to PATH:"
echo ""

DETECTED_SHELL="$(basename "${SHELL:-bash}")"
case "$DETECTED_SHELL" in
    zsh)  RC_FILE="$HOME/.zshrc" ;;
    bash) RC_FILE="$HOME/.bashrc" ;;
    *)    RC_FILE="$HOME/.profile" ;;
esac

echo "  echo 'export PATH=\"$QE_PREFIX/bin:\$PATH\"' >> $RC_FILE && source $RC_FILE"
echo ""
