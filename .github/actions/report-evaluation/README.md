# Report Evaluation

Run and report the evaluation or qualification of PBPK model.

## Usage

```yml
- name: Run evaluation
  uses: pchelle/osp-actions/report-evaluation@main
  with:
    model-repo: 7E3-Model
    model-version: '1.0'
    snapshot: '7E3'
    pk-sim-version: '11.3.208'
    qualification-framework-version: '3.2'
    save-model-file: true
    save-pdf: true
    save-artifact: true
```

## Inputs

| Name | Is Required | Default Value | Description |
|------|-------------|---------------|-------------|
| `model-repo` | `true` | | Name of Github OSP repository from which to get the Model |
| `model-version` | `true` | `1.0` | Tag version of the model OSP repository |
| `snapshot` | `true` | `model-repo` | Name of the snapshot (.json) file |
| `workflow-script` | `false` | `NULL` | Path of workflow R script that creates the function to run the qualification if not default<br>(default corresponds to case insensitive `evaluation/workflow.R` path). |
| `additional-project-urls` | `false` | `NULL` | URL of additional project snapshots to export as pksim5 projects.<br>If multiple projects are exported, they need to be separated by a pipe character: `|` |
| `pk-sim-version` | `false` | `11.3.208` | Version of PK-Sim |
| `qualification-framework-version` | `false` | `3.2` | Version of the Qualification Framework |
| `save-model-file` | `true` | `true` | Save pksim5 model file |
| `save-pdf` | `true` | `true` | Save evalution report as PDF |
| `save-word` | `false` | `false` | Save evalution report as word document |
| `save-artifact`| `true` | `true` | Save the report as artifact |


## Outputs

If `save-artifact: true`, the action will output `artifact-url`

