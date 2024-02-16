using Base: @kwdef
using Distributions
using StatsBase: mean

"""ModelParams contains all the variables that are constant across simulations"""
@kwdef struct ModelParams
    house::House
    years::Vector{Int}
    n_mc_samples::Int = 10_000
end

"""A SOW contains all the variables that may vary from one simulation to the next"""
struct SOW{T<:Real}
    slr::Oddo17SLR # the parameters of sea-level rise
    surge_dist::Distributions.UnivariateDistribution # the distribution of storm surge
    discount_rate::T # the discount rate, as a percentage (e.g., 2% is 0.02)
end

"""
In this model, we only hvae one decision variable: how high to elevate the house.
"""
struct Action{T<:Real}
    Δh_ft::T
end
function Action(Δh::T) where {T<:Unitful.Length}
    Δh_ft = ustrip(u"ft", Δh)
    return Action(Δh_ft)
end

"""Run the model for a given action and SOW"""
function run_sim(a::Action, sow::SOW, p::ModelParams)

    # first, we calculate the cost of elevating the house
    construction_cost = elevation_cost(p.house, a.Δh_ft)

    # next, we calculate expected annual damages for each year
    eads = map(p.years) do year

        # calculate the sea level for this year
        slr_ft = sow.slr(year)

        # Monte Carlo simulation
        storm_surges_ft = rand(sow.surge_dist, p.n_mc_samples)
        depth_ft_gauge = storm_surges_ft .+ slr_ft
        depth_ft_house = depth_ft_gauge .- (p.house.height_above_gauge_ft + a.Δh_ft)

        # calculate the expected annual damages
        damages_frac = p.house.ddf.(depth_ft_house) ./ 100 # convert to fraction
        mean(damages_frac) * p.house.value_usd
    end

    # finally, we aggregate the costs and benefits to get the net present value
    years_idx = p.years .- minimum(p.years) # 0, 1, 2, 3, .....
    discount_fracs = (1 - sow.discount_rate) .^ years_idx

    ead_npv = sum(eads .* discount_fracs)
    return -(ead_npv + construction_cost)
end
