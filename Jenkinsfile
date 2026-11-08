// ServerForge release pipeline (Jenkins declarative syntax).
// lint -> unit tests -> build artifact -> staging (converge + deploy) ->
// manual approval -> production (converge + rolling deploy, one server at a time)
//
// The same steps run in GitHub Actions (.github/workflows/ci.yml); see
// docs/JENKINS-vs-GITHUB-ACTIONS.md for a side-by-side comparison.
pipeline {
  agent { label 'ansible' }

  options {
    timestamps()
    ansiColor('xterm')
    disableConcurrentBuilds()           // two releases must never race each other
    buildDiscarder(logRotator(numToKeepStr: '20'))
    timeout(time: 45, unit: 'MINUTES')
  }

  parameters {
    choice(name: 'ACTION', choices: ['release', 'rollback-production', 'harden-only'],
           description: 'release = full pipeline; rollback-production = previous release on production; harden-only = security baseline on all servers')
    booleanParam(name: 'BROKEN_RELEASE', defaultValue: false,
                 description: 'Ship a release that fails its health check, to watch the automatic rollback stop it on staging')
  }

  environment {
    INV = 'lab'
    ANSIBLE_FORCE_COLOR = '1'
    PY_COLORS = '1'
  }

  stages {
    stage('Lint') {
      steps {
        sh 'yamllint --strict .'
        sh 'ansible-lint --offline'
        sh 'ruff check app tools'
      }
    }

    stage('Unit tests') {
      steps {
        sh 'mkdir -p reports && cd app && pytest -q --junitxml=../reports/junit-app.xml'
        sh 'pytest -q tools/tests --junitxml=reports/junit-tools.xml'
      }
      post { always { junit 'reports/junit-*.xml' } }
    }

    stage('Build artifact') {
      when { expression { params.ACTION == 'release' } }
      steps {
        script {
          def base = readFile('app/VERSION').trim()
          env.APP_VERSION = "${base}-build.${env.BUILD_NUMBER}"
        }
        sh "VERSION=${env.APP_VERSION} bash scripts/build-app.sh ${params.BROKEN_RELEASE ? '--broken' : ''}"
        archiveArtifacts artifacts: 'dist/*', fingerprint: true
      }
    }

    stage('Staging') {
      when { expression { params.ACTION == 'release' } }
      steps {
        withCredentials([sshUserPrivateKey(credentialsId: 'lab-ssh', keyFileVariable: 'SF_SSH_KEY')]) {
          sh 'mkdir -p .keys'
          sh 'ansible-playbook playbooks/site.yml --limit staging'
          sh 'ansible-playbook playbooks/deploy.yml -e target=staging -e app_artifact="$(ls -1t $PWD/dist/serverforge-app-*.tar.gz | head -n 1)"'
        }
      }
    }

    stage('Approve production') {
      when { expression { params.ACTION == 'release' } }
      steps {
        timeout(time: 30, unit: 'MINUTES') {
          input message: "Staging runs ${env.APP_VERSION}. Release it to production?", ok: 'Release'
        }
      }
    }

    stage('Production') {
      when { expression { params.ACTION == 'release' } }
      steps {
        withCredentials([sshUserPrivateKey(credentialsId: 'lab-ssh', keyFileVariable: 'SF_SSH_KEY')]) {
          sh 'mkdir -p .keys'
          sh 'ansible-playbook playbooks/site.yml --limit production'
          sh 'ansible-playbook playbooks/deploy.yml -e target=production -e app_artifact="$(ls -1t $PWD/dist/serverforge-app-*.tar.gz | head -n 1)"'
        }
      }
    }

    stage('Rollback production') {
      when { expression { params.ACTION == 'rollback-production' } }
      steps {
        withCredentials([sshUserPrivateKey(credentialsId: 'lab-ssh', keyFileVariable: 'SF_SSH_KEY')]) {
          sh 'mkdir -p .keys && ansible-playbook playbooks/rollback.yml -e target=production'
        }
      }
    }

    stage('Harden all servers') {
      when { expression { params.ACTION == 'harden-only' } }
      steps {
        withCredentials([sshUserPrivateKey(credentialsId: 'lab-ssh', keyFileVariable: 'SF_SSH_KEY')]) {
          sh 'mkdir -p .keys && ansible-playbook playbooks/harden.yml'
        }
      }
    }
  }

  post {
    success { echo "Done: ${params.ACTION} ${env.APP_VERSION ?: ''}" }
    failure { echo 'Failed. A failed health check has already been rolled back on the server where it happened - see the "Roll back" task in the log.' }
    cleanup { cleanWs(deleteDirs: true, notFailBuild: true) }
  }
}
