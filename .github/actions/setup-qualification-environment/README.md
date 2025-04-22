# Setup Qualification Environment

Install OSPSuite tools and Qualification Framework based on csv file input

## Usage

```yml
- name: Setup Qualification Environment
  uses: pchelle/osp-actions/setup-qualification-environment@main
  with:
    tools-path: tools.csv
    from-cache: true
```

> [!TIP]
> To view and download a template for `tools.csv`, click on the following link [&#128279;](../tools.csv).
> 
> Then, update and add the file to your repository.

## Inputs

This action requires:

- __`tools-path`__: the path of a csv file defining the tools and versions to install

This action can optionally use:

- __`install-pandoc`__: boolean defining to install Pandoc in the environment

The csv file in __`tools-path`__ indicates software and software versions to be installed in environment before running the qualifications of the models.
If a link is defined in the `URL` column, the installation will use the software from the link as is instead of searching from the version.
Please ensure compatibility between their versions.
The following available tools to installed are detailed below:

- [__ospsuite-R__](https://www.open-systems-pharmacology.org/OSPSuite-R/) : R package providing the functionality of loading, manipulating, and simulating the simulations created in the Open Systems Pharmacology Software tools PK-Sim and MoBi.
- [__Reporting Engine__](https://www.open-systems-pharmacology.org/OSPSuite.ReportingEngine/): R package providing a framework in R to design and create reports evaluating PBPK models developed in the Open Systems Pharmacology ecosystem.
- [__RUtils__](https://www.open-systems-pharmacology.org/OSPSuite.RUtils/): R package providing utility functions for Open Systems Pharmacology R Packages
- [__TLF__](https://www.open-systems-pharmacology.org/TLF-Library/): R package providing an object-oriented framework to create tables and figures, which are used by R packages in the Open Systems Pharmacology ecosystem
- [__rClr__](https://github.com/Open-Systems-Pharmacology/rClr): R package for accessing .NET. This package has been deprecated in favor of `{rSharp}`.
- [__rSharp__](https://www.open-systems-pharmacology.org/rSharp/): R package providing access to .NET libraries from R. It allows to create .NET objects, access their fields, and call their methods
- [__Qualification Runner__](https://github.com/Open-Systems-Pharmacology/QualificationRunner): Qualification runner in charge of managing a qualification workflow
- [__Qualification Framework__](https://docs.open-systems-pharmacology.org/shared-tools-and-example-workflows/qualification): Enables an automated validation of various scenarios (use-cases) supported by the OSP platform
- [__PK-Sim__](https://github.com/Open-Systems-Pharmacology/PK-Sim): Portable version of the comprehensive software tool for whole-body physiologically based pharmacokinetic modeling


## Outputs

The action exports `tools-table` corresponding to the markdown formatted version of the table defined by the csv file
