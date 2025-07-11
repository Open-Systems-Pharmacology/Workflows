# Download and unzip

Download a zip from an OSPSuite repository and extract as a specific path using R

## Usage

```yml
- name: Get tools versions
  id: download-repo
  uses: Open-Systems-Pharmacology/Workflows/.github/actions/downloader@main
  with:
    repo: '7E3-Model'
    version: '1.0'
    extract-path: '7E3'

- name: Check extracted repo
  id: check-repo
  run: |
    ls 7E3
  shell: bash
```

## Inputs

- __`repo`__: Name of Github OSP repository from which to download
- __`version`__: Version of Github OSP repository can be either __tag__ or __branch__ version. Default is `'main'`
- __`extract-path`__: Direcory of extracted repo content
- __`url`__: If provided, is used instead of repo and version
