```text
AAP-with-OCP-Workshop
├── README.md            # Workshop instructions & bootstrap
├── .gitignore           # Excludes .env, ai_docs/, .agents/
├── .env.example         # Template for secrets (never committed)
├── scripts/
│   ├── 01_install_aap_operator.sh
│   ├── 02_deploy_showroom.sh
│   └── 99_cleanup.sh
├── playbooks/           # One play per agenda module
│   ├── dynamic_inventory.yml
│   ├── idempotent_ocp.yml
│   ├── rbac_automation.yml
│   ├── jinja2_templating.yml
│   └── error_handling.yml
├── roles/               # Re‑usable logic for playbooks
│   └── ...
├── specs/               # Markdown requirement docs
│   ├── dynamic-inventory.md
│   └── ...
├── ai_docs/             # Generated: latest OCP & AAP docs (git‑ignored)
└── .agents/             # Generated: custom agent command sets (git‑ignored)
```
