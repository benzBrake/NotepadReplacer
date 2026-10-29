#!/bin/sh
set -eu
configuration=${1:-Release}
case "$configuration" in
    Debug|Release|RelWithDebInfo|MinSizeRel) ;;
    *) echo 'Invalid build configuration' >&2; exit 1 ;;
esac

umask 077
mkdir -p /work/installer /work/dist/context-menu-package/content
signing_tmp=$(mktemp -d)
trap 'rm -rf "$signing_tmp"' EXIT
# Secrets are read-only runtime mounts, never image layers or build arguments.
openssl pkcs12 -in /signing/certificate.pfx -passin file:/signing/password \
    -clcerts -nokeys -out "$signing_tmp/certificate.pem"
openssl pkcs12 -in /signing/certificate.pfx -passin file:/signing/password \
    -nocerts -nodes -out "$signing_tmp/key.pem"
subject=$(openssl x509 -in "$signing_tmp/certificate.pem" -noout -subject -nameopt RFC2253)
if [ "$subject" != 'subject=CN=Notepad Replacer' ]; then
    echo 'The signing certificate subject must be CN=Notepad Replacer.' >&2
    exit 1
fi
openssl x509 -in "$signing_tmp/certificate.pem" -checkend 2592000 -noout

cp /source/installer/* /work/installer/
cp /source/LICENSE /source/ADDITIONAL-TERMS.md /source/replacer.ico /work/
package=/work/dist/context-menu-package
cp /work/installer/AppxManifest.xml /work/installer/logo.png "$package/content/"
makemsix pack -d "$package/content" -p "$package/unsigned.msix"
osslsigncode sign -certs "$signing_tmp/certificate.pem" -key "$signing_tmp/key.pem" \
    -in "$package/unsigned.msix" -out "$package/NotepadReplacer.msix"
osslsigncode verify -CAfile "$signing_tmp/certificate.pem" -in "$package/NotepadReplacer.msix"
openssl x509 -in "$signing_tmp/certificate.pem" -outform DER -out "$package/NotepadReplacer.cer"

mkdir /work/installer-output
xvfb-run -a wine 'C:\InnoSetup\ISCC.exe' \
    "/DBuildConfiguration=$configuration" '/DComponentsDirectory=Z:\components' \
    '/OZ:\work\installer-output' 'Z:\work\installer\NotepadReplacer.iss'
mkdir -p /out/context-menu-package
cp "$package/NotepadReplacer.msix" "$package/NotepadReplacer.cer" /out/context-menu-package/
cp /work/installer-output/NotepadReplacerSetup.exe /out/
