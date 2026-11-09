# Quick start

1. Copy `config.env.example` to `config.env`.
2. Edit `LOCATION`, globally unique `STORAGE`, `SSH_SOURCE`, and `SSH_KEY`.
3. Run from Bash:

```bash
chmod +x scripts/*.sh
./scripts/create-infrastructure.sh
./scripts/deploy-demo.sh
./scripts/verify.sh
./scripts/scale-out.sh
./scripts/scale-in.sh
```

4. Browse to the public IP of the existing VM shown by `scripts/verify.sh`.
5. Delete the lab when finished with `./scripts/cleanup.sh`.

Read [README.md](README.md) for the full UI-style walkthrough, architecture, requirements, and teaching notes.
