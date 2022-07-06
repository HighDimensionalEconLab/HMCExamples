using StatsPlots
using MCMCChains
using Dates
using Statistics
using MAT
using Base.Threads, Base.Iterators

function cummean!(p, xs, array::Vector; title = "", fancy_time = -1)
    M = zeros(length(array))
    S = zeros(Union{Float64, Missing}, length(array))

    for i in 1:length(array)
        M[i] = mean(skipmissing(array[1:i]))
        S[i] = std(skipmissing(array[1:i]))
    end

    return plot!(p, xs, M, label=false, title=title, alpha=0.5, xlim=(0,1.1),
                xticks = (range(0, 1, length=4), ["0 minutes", "", "", "$fancy_time"]),
                xlabel = "Compute time")
end

include_vars = ["α", "β_draw", "ρ"]

var_ylim = Dict(
    "α" => (0.2, 0.45), 
    "β_draw" => (0,1), 
    "ρ" => (0,1)
)

mapping = Dict("α"=>"alpha", "β_draw"=>"beta_draw", "ρ"=>"rho")

for (folder, oldfoldername) in [(".experiments/benchmarks_dynare/dynare_chains_1", "dynare_chains_1"), (".experiments/benchmarks_dynare/dynare_chains_2", "dynare_chains_2")]
    files = readdir(folder)
    durations = []
    results = []
    for file in files
        mat = matread(joinpath(folder, file))
        push!(durations, mat["rt"] / 2)
        push!(results, [mat["x2"] mat["logpo2"]])
    end
    max_time = quantile(durations, [0.75])[1]
    adj_durations = durations ./ max_time

    fancy_time = round(Second(floor(max_time)), Minute)

    p = []
    p1 = []
    for _ in include_vars
        push!(p, plot())
        push!(p1, plot())
    end

    @threads for ((i, data), (j, variable)) in collect(product(collect(enumerate(results)), collect(enumerate(include_vars))))
        println(files[i], "  ", variable, " ", j)
        c = Chains(data, ["α", "β_draw", "ρ", "lp"])
        d = range(0, 1, length=size(c, 1))
        cummean!(p[j], d, c[:,variable,1].data; fancy_time=fancy_time)
        plot!(p1[j], d, c[:,variable,1].data,
            alpha=0.3, legend=false, xlim=(0,1.1),
            ylim = var_ylim[variable],
            xticks = (range(0, 1, length=4), ["0 minutes", "", "", "$fancy_time"]),
            xlabel = "Compute time")
    end
    j = 0
    for variable in include_vars 
        j += 1
        xlabel!(p[j], "Compute time")

        savefig(
            p[j],
            ".figures/cummean_$(mapping[variable])_$(oldfoldername).png"
        )
        savefig(
            p1[j],
            ".figures/trace_$(mapping[variable])_$(oldfoldername).png"
        )
    end
end
