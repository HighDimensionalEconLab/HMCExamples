# Entry for script
function main_FVGQ_2_joint(args=ARGS)
    d = parse_commandline_FVGQ_2_joint(args)
    return estimate_FVGQ_2_joint((; d...)) # to named tuple
end

function estimate_FVGQ_2_joint(d)
    # Or move these into main package when loading?
    Turing.setadbackend(:zygote)
    HMCExamples.set_BLAS_threads()

    # load data relative to the current path
    data_path = joinpath(pkgdir(HMCExamples), d.data_path)
    df = Matrix(DataFrame(CSV.File(data_path)))
    z = [df[i, :] for i in 1:size(df, 1)]

    ϵ0 = Matrix(DataFrame(CSV.File(joinpath(pkgdir(HMCExamples), "data/epsilons_burnin_FVGQ20_2.csv");header=false)))

    # Create the perturbation and the turing models
    m = PerturbationModel(HMCExamples.FVGQ20)
    p_d = (β = d.beta, h = d.h, κ = d.kappa, χ = d.chi, γR = d.gamma_R, γΠ = d.gamma_Pi, Πbar = d.Pi_bar, ρd = d.rho_d, ρφ = d.rho_psi, ρg = d.rho_g, g_bar = d.g_bar, σ_A = d.sigma_A, σ_d = d.sigma_d, σ_φ = d.sigma_psi, σ_μ = d.sigma_mu, σ_m = d.sigma_m, σ_g = d.sigma_g, Λμ = d.Lambda_mu, ΛA = d.Lambda_A)
    p_f = (ϑ = 1.0, δ = d.delta, ε = d.epsilon, ϕ = d.phi, γ2 = d.gamma2, Ω_ii = d.Omega_ii, α = d.alpha, γy = d.gamma_y, θp = d.theta_p)
    c = SolverCache(m, Val(2), p_d)
    #create H prior
    Hx = zeros(6, m.n_x)
    Hy = zeros(6, m.n_y)
    Hy[1, 19] = 1 # Π
    Hy[2, 20] = 1 # R
    Hy[3, 18] = 1 # dw, trend is μz
    Hy[4, 18] = 1 # dy, trend is μz
    Hy[6, 24] = 1 # μ-1
    params = (β = Gamma_tr(d.beta_prior[1],d.beta_prior[2]),
    h = Beta_tr(d.h_prior[1], d.h_prior[2]),
    κ = (d.kappa_prior[1], d.kappa_prior[2], d.kappa_prior[3], d.kappa_prior[4]),
    γΠ = (d.gamma_Pi_prior[1], d.gamma_Pi_prior[2], d.gamma_Pi_prior[3], d.gamma_Pi_prior[4]),
    χ = Beta_tr(d.chi_prior[1], d.chi_prior[2]),
    γR = Beta_tr(d.gamma_R_prior[1], d.gamma_R_prior[2]),
    Πbar = Gamma_tr(d.Pi_bar_prior[1], d.Pi_bar_prior[2]),
    ρd = Beta_tr(d.rho_d_prior[1], d.rho_d_prior[2]),
    ρφ = Beta_tr(d.rho_psi_prior[1], d.rho_psi_prior[2]),
    ρg = Beta_tr(d.rho_g_prior[1], d.rho_g_prior[2]),
    g_bar = Beta_tr(d.g_bar_prior[1], d.g_bar_prior[2]),
    σ_A = InvGamma_tr(d.sigma_A_prior[1], d.sigma_A_prior[2]),
    σ_d = InvGamma_tr(d.sigma_d_prior[1], d.sigma_d_prior[2]),
    σ_φ = InvGamma_tr(d.sigma_psi_prior[1], d.sigma_psi_prior[2]),
    σ_μ = InvGamma_tr(d.sigma_mu_prior[1], d.sigma_mu_prior[2]),
    σ_m = InvGamma_tr(d.sigma_m_prior[1], d.sigma_m_prior[2]),
    σ_g = InvGamma_tr(d.sigma_g_prior[1], d.sigma_g_prior[2]),
    Λμ = Gamma_tr(d.Lambda_mu_prior[1], d.Lambda_mu_prior[2]),
    ΛA = Gamma_tr(d.Lambda_A_prior[1], d.Lambda_A_prior[2]),
    Hx = Hx,
    Hy = Hy)

    turing_model = FVGQ20_joint(
        z, m, p_f, params, c, PerturbationSolverSettings(;ϵ_BK = d.epsilon_BK, print_level = d.print_level)
    )

    # Sampler
    name = "FQGV-joint-2-s$(d.num_samples)-seed$(d.seed)"
    include_vars = ["β_draw", "h", "κ",  "χ", "γR",  "γΠ", "Πbar_draw", "ρd", "ρφ", "ρg", "g_bar", "σ_A", "σ_d", "σ_φ", "σ_μ", "σ_m", "σ_g", "Λμ", "ΛA"]  # variables to log
    callback = TensorBoardCallback(d.results_path; name, include=include_vars)
    num_adapts = convert(Int64, floor(d.num_samples * d.adapts_burnin_prop))

    Random.seed!(d.seed)
    @info "Generating $(d.num_samples) samples with $(num_adapts) adapts across $(d.num_chains) chains"

    chain = sample(
        turing_model,
        NUTS(num_adapts, d.target_acceptance_rate; d.max_depth),
        MCMCThreads(),
        d.num_samples,
        d.num_chains;
        init_params=[p_d..., ϵ0],
        progress=true,
        save_state=true,
        callback,
    )

    # Store parameters in log directory
    parameter_save_path = joinpath(callback.logger.logdir, "parameters.json")

    @info "Storing Parameters at $(parameter_save_path) "
    open(parameter_save_path, "w") do f
        write(f, JSON.json(d))
    end

    # Calculate and save results into the logdir
    calculate_experiment_results(chain, callback.logger, include_vars)
end

function parse_commandline_FVGQ_2_joint(args)
    s = ArgParseSettings(; fromfile_prefix_chars=['@'])

    # See the appropriate _defaults.txt file for the default vvalues.
    @add_arg_table! s begin
        "--data_path"
        help = "relative path to data from the root of the package"
        arg_type = String
        "--beta"
        help = "Initialization of parameters"
        arg_type = Float64
        "--h"
        help = "Initialization of parameters"
        arg_type = Float64
        "--kappa"
        help = "Initialization of parameters"
        arg_type = Float64
        "--chi"
        help = "Initialization of parameters"
        arg_type = Float64
        "--gamma_R"
        help = "Initialization of parameters"
        arg_type = Float64
        "--gamma_Pi"
        help = "Initialization of parameters"
        arg_type = Float64
        "--Pi_bar"
        help = "Initialization of parameters"
        arg_type = Float64
        "--rho_d"
        help = "Initialization of parameters"
        arg_type = Float64
        "--rho_psi"
        help = "Initialization of parameters"
        arg_type = Float64
        "--rho_g"
        help = "Initialization of parameters"
        arg_type = Float64
        "--g_bar"
        help = "Initialization of parameters"
        arg_type = Float64
        "--sigma_A"
        help = "Initialization of parameters"
        arg_type = Float64
        "--sigma_d"
        help = "Initialization of parameters"
        arg_type = Float64
        "--sigma_psi"
        help = "Initialization of parameters"
        arg_type = Float64
        "--sigma_mu"
        help = "Initialization of parameters"
        arg_type = Float64
        "--sigma_m"
        help = "Initialization of parameters"
        arg_type = Float64
        "--sigma_g"
        help = "Initialization of parameters"
        arg_type = Float64
        "--Lambda_mu"
        help = "Initialization of parameters"
        arg_type = Float64
        "--Lambda_A"
        help = "Initialization of parameters"
        arg_type = Float64
        "--delta"
        help = "Value of fixed parameters"
        arg_type = Float64
        "--epsilon"
        help = "Value of fixed parameters"
        arg_type = Float64
        "--phi"
        help = "Value of fixed parameters"
        arg_type = Float64
        "--gamma2"
        help = "Value of fixed parameters"
        arg_type = Float64
        "--Omega_ii"
        help = "Value of fixed parameters"
        arg_type = Float64
        "--alpha"
        help = "Value of fixed parameters"
        arg_type = Float64
        "--gamma_y"
        help = "Value of fixed parameters"
        arg_type = Float64
        "--theta_p"
        help = "Value of fixed parameters"
        arg_type = Float64

        "--kappa_prior"
        help = "Value of fixed parameters"
        arg_type = Vector{Float64}
        "--gamma_Pi_prior"
        help = "Value of fixed parameters"
        arg_type = Vector{Float64}

        "--beta_prior"
        help = "Parameters for the prior"
        arg_type = Vector{Float64}
        "--h_prior"
        help = "Parameters for the prior"
        arg_type = Vector{Float64}
        "--chi_prior"
        help = "Parameters for the prior"
        arg_type = Vector{Float64}
        "--gamma_R_prior"
        help = "Parameters for the prior"
        arg_type = Vector{Float64}
        "--Pi_bar_prior"
        help = "Parameters for the prior"
        arg_type = Vector{Float64}
        "--rho_d_prior"
        help = "Parameters for the prior"
        arg_type = Vector{Float64}
        "--rho_psi_prior"
        help = "Parameters for the prior"
        arg_type = Vector{Float64}
        "--rho_g_prior"
        help = "Parameters for the prior"
        arg_type = Vector{Float64}
        "--g_bar_prior"
        help = "Parameters for the prior"
        arg_type = Vector{Float64}

        "--sigma_A_prior"
        help = "Parameters for the prior"
        arg_type = Vector{Float64}
        "--sigma_d_prior"
        help = "Parameters for the prior"
        arg_type = Vector{Float64}
        "--sigma_psi_prior"
        help = "Parameters for the prior"
        arg_type = Vector{Float64}
        "--sigma_mu_prior"
        help = "Parameters for the prior"
        arg_type = Vector{Float64}
        "--sigma_m_prior"
        help = "Parameters for the prior"
        arg_type = Vector{Float64}
        "--sigma_g_prior"
        help = "Parameters for the prior"
        arg_type = Vector{Float64}

        "--Lambda_mu_prior"
        help = "Parameters for the prior"
        arg_type = Vector{Float64}
        "--Lambda_A_prior"
        help = "Parameters for the prior"
        arg_type = Vector{Float64}


        help = "Parameters for the prior"
        arg_type = Vector{Float64}
        "--num_samples"
        help = "samples to draw in chain"
        arg_type = Int64
        "--num_chains"
        help = "number of chains to sample"
        arg_type = Int64
        "--adapts_burnin_prop"
        help = "Proportion of Adaptations burned in"
        arg_type = Float64
        "--target_acceptance_rate"
        help = "Target acceptance rate for dual averaging for NUTS"
        arg_type = Float64
        "--max_depth"
        help = "Maximum depth for NUTS"
        arg_type = Int64
        "--seed"
        help = "Random number seed"
        arg_type = Int64
        "--results_path"
        arg_type = String
        help = "Location to store results and logs"
        "--print_level"
        arg_type = Int64
        help = "Print level for output during sampling"
        "--epsilon_BK"
        arg_type = Float64
        help = "Threshold for Checking Blanchard-Khan condition"        
        "--use_solution_cache"
        arg_type = Bool
        help = "Use solution cache in perturbation solutions"

    end
    
    args_with_default = vcat("@$(pkgdir(HMCExamples))/src/FVGQ_2_joint_defaults.txt", args)
    return parse_args(args_with_default, s; as_symbols=true)

end
