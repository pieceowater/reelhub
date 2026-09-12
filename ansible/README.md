# ansible/

The automation that configures the stack. Full documentation lives in the
[project README](../README.md).

| File | What it is |
|---|---|
| `deploy.yml` | The playbook. Every step is commented — read it top to bottom to see exactly what gets configured and why. |
| `vars.yml.example` | Template for your settings. Copy to `vars.yml`. |
| `vars.yml` | Your real ports, paths and passwords. Gitignored. |
| `inventory.ini` | One host: localhost, over a local connection. Nothing is deployed remotely. |
| `ansible.cfg` | Points at the inventory so `-i` is not needed. |

```bash
# from the repo root
make deploy

# or directly
cd ansible && ansible-playbook deploy.yml
```
