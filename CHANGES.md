# Replacement repository changes

The previous Wine execution path has been removed from the replacement repository. The project now treats the existing Windows 11 VM as the Inventor runtime and exposes Inventor automation to Ubuntu through an authenticated bridge.

Key changes:

- Windows-side FastAPI bridge with pywin32 Inventor COM automation.
- One dedicated STA COM worker thread; Inventor requests are serialized.
- Attach to an already-running Inventor instance or start it automatically.
- IPT/IAM/STEP/STP input support plus ZIP assembly bundles.
- Metadata, STL, and STEP returned together in one response archive.
- API-token authentication for all Inventor operations.
- Windows PowerShell install/start/stop/test scripts.
- Interactive-user scheduled task rather than a Session 0 service.
- Linux libvirt VM-IP discovery and end-to-end health scripts.
- Generated matching client/bridge token stored only in gitignored config files.
