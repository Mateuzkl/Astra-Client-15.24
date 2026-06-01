# tools/sign — Windows code-signing toolchain

This directory hosts the Windows code-signing toolchain used by the release
pipeline (vc17 `Sign` build step). The signing binary (`signtool.exe`) and its
required runtime DLLs / manifests live here and are committed so that any
developer can produce a signed Windows build without installing the Windows SDK.

## What lives here (committed)

- `signtool.exe` + `signtool.exe.manifest`
- `mssign32.dll` + `Microsoft.Windows.Build.Signing.mssign32.dll.manifest`
- `wintrust.dll` + `Microsoft.Windows.Build.Signing.wintrust.dll.manifest`

These are Microsoft-redistributable signing tools. They contain no secret
material and are safe to commit.

## What does NOT live here (intentional)

- `certificate.pfx` — the actual code-signing certificate.

A `.pfx` is a PKCS#12 bundle that contains the **private key** of the signing
certificate. Committing it to a public repository is a security incident: anyone
who clones the repo can sign arbitrary binaries as us. For that reason the
`.pfx` is intentionally **not** committed and `tools/sign/*.pfx` should be added
to `.gitignore`.

> The previous `certificate.pfx` that had been committed to this directory was
> removed in the `upgrade/protocol-15.24` branch as part of the P0 open-source
> hygiene pass. If you ever fetched the repo before that cleanup, treat the old
> certificate as compromised — rotate it with your CA and revoke the old one.

## Signing a release locally

1. Obtain your developer code-signing certificate (`.pfx`) from your CA / vault.
2. Drop it at `tools/sign/certificate.pfx` (this path is gitignored — verify
   with `git status` that it does **not** appear as an untracked file before
   committing anything).
3. Run the existing `Sign` build step in the vc17 solution (Visual Studio
   2022), or invoke `signtool.exe` from this directory manually, e.g.:

   ```
   tools\sign\signtool.exe sign ^
       /f tools\sign\certificate.pfx ^
       /p <password> ^
       /tr http://timestamp.digicert.com ^
       /td sha256 ^
       /fd sha256 ^
       path\to\AstraClient.exe
   ```

4. After signing, delete the `.pfx` from your working tree (or keep it only in
   an encrypted vault). Never commit it.

## CI / release builds

Production release signing should happen on a trusted build machine where the
`.pfx` (or, preferably, an HSM-backed certificate) is provisioned out of band
and never written to the repository.
