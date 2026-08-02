name: Azure Function Deployment

# Runs only when you manually click "Run workflow"
on:
  workflow_dispatch:

permissions:
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout Repository
        uses: actions/checkout@v4

      - name: Azure Login
        uses: azure/login@v2
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}

      - name: Verify Repository Structure
        run: |
          pwd
          ls -R

      - name: Execute setup.ps1
        shell: pwsh
        working-directory: azfunctionapp/azfunctionadmitcard
        run: |
          ./setup.ps1
