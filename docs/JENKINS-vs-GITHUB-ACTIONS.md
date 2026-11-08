# Jenkins vs GitHub Actions: the same pipeline twice

This repository runs its checks in both tools, because companies use both, and many
of them are moving from Jenkins to Actions.

| Step | Jenkins (`Jenkinsfile`) | GitHub Actions (`.github/workflows/ci.yml`) |
|---|---|---|
| Where it runs | Your own agent (`jenkins-agent` container) | GitHub-hosted runner (`ubuntu-24.04`) |
| Trigger | Manual build, or SCM polling / webhook | `push`, `pull_request`, `workflow_dispatch` |
| Tools on the runner | Baked into the agent image (`jenkins/agent.Dockerfile`) | Installed in the job (`pip install -r requirements-dev.txt`) |
| Lint + tests | `stage('Lint')`, `stage('Unit tests')` + `junit` | `lint-and-test` job + step summary |
| Secrets | Jenkins credentials + `withCredentials(sshUserPrivateKey)` | Repository/environment secrets; OIDC for AWS (no stored keys) |
| Manual approval | `input` step (any logged-in user, 30-minute timeout) | Environment protection rules (required reviewers) |
| Artifacts | `archiveArtifacts` + fingerprints | `actions/upload-artifact` |
| Nightly job | `triggers { cron('H 2 * * *') }` in `Jenkinsfile.drift` | `on: schedule` (see `auto-stop.yml`) |
| Config of the tool itself | `plugins.txt` + `casc.yaml` (JCasC) | Nothing to host; workflow YAML is the config |
| Cost | Your servers + your time patching Jenkins and plugins | Free for public repos; per-minute for private |

## When I would pick which

- **Jenkins:** builds must run inside a private network, you need very custom agents, or the
  company already runs it well. Budget time for plugin updates and security advisories.
- **GitHub Actions:** the code is on GitHub and the team is small. Nothing to host, OIDC to
  every cloud, a huge marketplace (pin actions to commit SHAs).

## Migrating a Jenkinsfile to Actions (the service version of this page)

1. Inventory the jobs: triggers, agents, credentials, plugins each job uses.
2. Map stages to jobs/steps (table above). Shared libraries become reusable workflows or
   composite actions.
3. Replace stored cloud keys with OIDC roles; move other credentials to environment secrets.
4. Run both in parallel for a week; compare results; then switch off the Jenkins job.
5. `gh actions-importer` (GitHub's official tool) can do a first draft of step 2.
