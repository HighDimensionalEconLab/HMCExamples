#!/bin/bash

# TODO can add whole sequence of steps here

# assumes that all scripts in run_dynare_samplers and run_samplers have executed

# figures
julia --project=scripts scripts/generate_paper_results/baseline_figures.jl
julia --project=scripts scripts/generate_paper_results/rbc_robustness_figures.jl
julia --project=scripts scripts/generate_paper_results/convert_frequentist_output.jl


# tables
python scripts/generate_paper_results/baseline_tables.py
python scripts/generate_paper_results/rbc_frequentist_tables.py
