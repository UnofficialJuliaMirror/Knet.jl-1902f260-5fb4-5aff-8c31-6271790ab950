# Based on https://github.com/cloud-oak/Tqdm.jl by @cloud-oak under Mozilla Public License 2.0
# Modified for Knet by Deniz Yuret

using Printf
import Base: length, size, iterate, eltype, IteratorSize, IteratorEltype, haslength, @propagate_inbounds

"""
    progress(f, itr; steps, seconds)
    progress(itr; o...) do x; f(x); end
    progress(itr; o...)
    progress!(...)

Return an iterator which acts exactly like `itr`, but prints a progressbar:

    ┣█████████████████▎  ┫ [86.83%, 903/1040, 01:36/01:50, 9.42i/s] 3.87835

Here `86.83%` is the percentage completed, `903` is the number of iterations completed,
`1040` is the total number of iterations. `01:36` is elapsed time, `01:50` is the estimated
total time, `9.42i/s` is the average number of iterations completed per second. If the speed
is less than 1, the average number of seconds per iteration (s/i) is reported instead.  The
bar, percent, total iterations, and estimated total time are omitted for iterators whose
size is unknown. `3.87835` is the output of `f` applied to the last value generated by itr.

The progress bar is updated and `f` is called with the most recent value of itr every
`steps` iterations or every `seconds` seconds in addition to the first and the last
iteration. If neither `steps` nor `seconds` is specified the default is to update every
second.
 
`f` can be specified by the first two forms above, if not specified (the third form) nothing
gets printed at the end of the line.  The last form, `progress!(...)`, is equivalent to
`(for x in progress(...) end)`, i.e.  iterates over the object created by `progress(...)`
and returns `nothing`.

"""
progress, progress!

mutable struct Progress{I}
    func
    iter::I
    steps
    seconds
    starttime::UInt
    lasttime::UInt
    lastiter::UInt
    curriter::UInt
    currval
end

progress(func::Base.Callable, iter::I; steps=0, seconds=0) where {I} =
    Progress{I}(func,iter,steps,seconds,0,0,0,0,nothing)

progress(iter; o...)=progress((x)->"",iter; o...)
progress!(x...; o...)=(for _ in progress(x...; o...) end)

IteratorSize(::Type{Progress{I}}) where {I} = IteratorSize(I)
IteratorEltype(::Type{Progress{I}}) where {I} = Base.EltypeUnknown()
length(p::Progress) = length(p.iter)

@propagate_inbounds function iterate(p::Progress, s...)
    if p.starttime == 0
        p.starttime = p.lasttime = time_ns()
        p.steps == p.seconds == 0 && (p.seconds = 1)
    end
    next = iterate(p.iter, s...)
    if next !== nothing
        p.curriter += 1
        (p.currval, s) = next
    end
    if ((next === nothing && p.curriter > 0) ||
        p.curriter == 1 || p.curriter == p.steps ||
        (p.steps != 0 && p.curriter == p.lastiter + p.steps) ||
        (p.seconds != 0 && time_ns() > p.lasttime + p.seconds*1e9))
        progressbar(p, next)
    end
    return next
end

function progressbar(p::Progress, next)
    fval_string = string(p.func(p.currval))
    currtime = time_ns()
    seconds = (currtime - p.starttime) * 1e-9
    speed = (next === nothing ? p.curriter / seconds : (p.curriter - p.lastiter) / ((currtime - p.lasttime) * 1e-9))
    p.lastiter, p.lasttime = p.curriter, currtime

    if haslength(p)
        ETA = (length(p) - p.curriter) / (p.curriter / seconds)
        percentage_string = string(@sprintf("%.2f%%",p.curriter/length(p)*100))
        status_string = string("[", percentage_string, 
                               ", ", p.curriter, "/", length(p), 
                               ", ", format_time(seconds), "/", format_time(seconds+ETA), 
                               ", ", format_speed(speed),
                               "] ")
    else
        status_string = string("[", p.curriter,
                               ", ", format_time(seconds),
                               ", ", format_speed(speed),
                               "] ")
    end

    print("\r")

    if (haslength(p))
        width = 20
        print("┣")
        cellvalue = length(p) / width
        full_cells, remain = divrem(p.curriter, cellvalue)
        full_cells = round(Int, full_cells)
        print(repeat("█", full_cells))
        if (full_cells < width)
	    part = floor(Int, 8 * remain / cellvalue)
	    print(EIGHTS[part])
            print(repeat(" ", width - full_cells - 1))
        end
        print("┫ ")
    end

    print(status_string)
    print(fval_string)
    next === nothing && println()
    return next
end

function format_time(seconds)
    if seconds != Inf
        mins,s  = divrem(round(Int,seconds), 60)
        h, m    = divrem(mins, 60)
    else
        h=0;m=Inf;s=Inf
    end
    if h!=0
         return @sprintf("%02d:%02d:%02d",h,m,s)
    else
         return @sprintf("%02d:%02d",m,s)
    end
end

format_speed(s)=(s >= 1 ? @sprintf("%.2fi/s",s) : @sprintf("%.2fs/i",1/s))

EIGHTS = Dict(0 => ' ',
	      1 => '▏',
	      2 => '▎',
	      3 => '▍',
	      4 => '▌',
	      5 => '▋',
	      6 => '▊',
	      7 => '▉',
	      8 => '█')
