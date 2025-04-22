# Get Tools Versions

Run and report the tools and versions from `tools-path`.

## Usage

```yml
- name: Get tools versions
  id: tools-versions
  uses: pchelle/osp-actions/get-tools-versions@main
  with:
    tools-path: 'tools.csv'

- name: Show tools information markdown table
  run: |
    echo ${{ steps.tools-versions.outputs.tools-table  }}
  shell: bash

- name: Show specific versions
  run: |
    echo 'PK-Sim version: ${{ steps.tools-versions.outputs.pk-sim  }}'
    echo 'Qualification framework version: ${{ steps.tools-versions.outputs.qualification-framework  }}'
  shell: bash
```

## Inputs

__`tools-path`__: Path a csv file defining the tools and versions to install

## Outputs

- __`tools-table`__: markdown formatted table of the csv file
- __`pk-sim`__: PK-Sim version
- __`qualification-framework`__: Qualification framework version
- __`ospsuite-r`__: OSPSuite-R package version
- __`reporting-engine`__: OSPSuite.ReportingEngine R package version

