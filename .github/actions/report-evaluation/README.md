# Report Evaluation

Run and report the evaluation or qualification of PBPK model.

> [!CAUTION]
> Evaluation reports assume that the workflows uses windows and has the qualification environment installed.
> 
> Thus, please check that jobs uses for instance `runs-on: windows-latest`.
> 
> Check that the previous step ran the action `setup-qualification-environment`.

## Usage

```yml
- name: Setup Qualification Environment
  uses: Open-Systems-Pharmacology/Workflows/.github/actions/setup-qualification-environment@main
  with:
    tools-path: 'tools.csv'

- name: Run Evaluation
  uses: Open-Systems-Pharmacology/Workflows/.github/actions/report-evaluation@main
  with:
    model-repo: '7E3-Model'
    model-version: '1.0'
    folder-name: '7E3'
    snapshot: '7E3'
    pk-sim-version: '11.3.208'
    qualification-framework-version: '3.2'
    save-model-file: 'true'
    save-pdf: 'true'
```

## Inputs

| Name | Is Required | Default Value | Description |
|------|-------------|---------------|-------------|
| `model-repo` | `true` | | Name of Github OSP repository from which to get the Model |
| `model-version` | `true` | | Tag or branch version of the model OSP repository |
| `folder-name` | `true` | | Name of the directory in which the report is created. |
| `snapshot` | `true` | `model-repo` | For evaluation, name of the snapshot (.json) file. |
| `evaluation` | `false` | `'true'` | Does the script run an evaluation ? |
| `workflow-script` | `false` | `NULL` | Path of workflow R script that creates the function to run the qualification if not default<br>(default corresponds to case insensitive `evaluation/workflow.R` path). |
| `additional-project-urls` | `false` | `NULL` | URL of additional project snapshots to export as pksim5 projects.<br>If multiple projects are exported, they need to be separated by a pipe character: `|` |
| `pk-sim-version` | `true` | | Version of PK-Sim |
| `qualification-framework-version` | `true` | | Version of the Qualification Framework |
| `save-model-file` | `true` | `'true'` | Save pksim5 model file |
| `save-pdf` | `true` | `'true'` | Save evalution report as PDF |
| `save-word` | `false` | `'false'` | Save evalution report as word document |
| `run-directory`| `false` | `'D:/0'` | Directory path where to download and run workflow |
