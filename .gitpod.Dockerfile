FROM julia:1.4.2

RUN apt-get update && \
    apt-get install -y \
    build-essential \
    cmake \
    python3 \
    python3-dev \
    python3-distutils \
    curl \
    ca-certificates \
    git \
    libgconf-2-4 \
    xvfb \
    libgtk-3-0 \
    dvipng \
    texlive-latex-recommended  \
    zip \
    libxt6 libxrender1 libxext6 libgl1-mesa-glx libqt5widgets5 # GR && \
    apt-get clean && rm -rf /var/lib/apt/lists/* # clean up

RUN apt-get update && \
    curl -sL https://deb.nodesource.com/setup_12.x | bash - && \
    apt-get install -y nodejs && \
    apt-get clean && rm -rf /var/lib/apt/lists/* # clean up  

RUN curl -kL https://bootstrap.pypa.io/get-pip.py | python3 && \
    pip3 install \
    numpy \
    sympy==1.5.* \
    pandas \
    matplotlib \
    numba


RUN mkdir -p ${HOME}/.julia/config && \
    echo '\
# set environment variables\n\
ENV["PYTHON"]=Sys.which("python3")\n\
ENV["JUPYTER"]=Sys.which("jupyter")\n\
\n\
import Pkg\n\
let\n\
    pkgs = ["Revise","OhMyREPL"]\n\
    for pkg in pkgs\n\
        if Base.find_package(pkg) === nothing\n\
            Pkg.add(pkg)\n\
        end\n\
    end\n\
end\n\
using OhMyREPL \n\
enable_autocomplete_brackets(false) \n\
atreplinit() do repl\n\
    try\n\
        @eval using Revise\n\
        @async Revise.wait_steal_repl_backend()\n\
    catch e\n\
        @warn(e.msg)\n\
    end\n\
end\n\
\n\
' >> ${HOME}/.julia/config/startup.jl && cat ${HOME}/.julia/config/startup.jl

RUN julia -e 'using InteractiveUtils; versioninfo()'

WORKDIR /work
ENV JULIA_PROJECT=/work
# create Project file at /work
RUN echo '\
name = "MyWorkflow"\n\
uuid = "7abf360e-92cb-4f35-becd-441c2614658a"\n\
' >> /work/Project.toml && cat /work/Project.toml

# Install Julia Packages with --project=/work
RUN julia -e 'using Pkg; \
Pkg.add([\
    PackageSpec(name="PackageCompiler", version="1.1.1"), \
    PackageSpec(name="Atom", version="0.12.11"), \
    PackageSpec(name="Juno", version="0.8.2"), \
    PackageSpec(name="OhMyREPL", version="0.5.5"), \
    PackageSpec(name="Revise", version="2.7.0"), \
    PackageSpec(name="Plots", version="1.3.3"), \
]); \
Pkg.pin(["PackageCompiler", "Atom", "Juno", "OhMyREPL", "Revise", "Plots"]); \
Pkg.add(["Plotly", "PlotlyJS", "ORCA"]); \
Pkg.add(["Documenter", "Literate", "Weave", "Franklin", "NodeJS"]); \
using NodeJS; run(`$(npm_cmd()) install highlight.js`); using Franklin; \
'

# suppress warning for related to GR backend
ENV GKSwstype=100
# Do Ahead of Time Compilation using PackageCompiler
# For some technical reason, we switch default user to root then we switch back again

RUN julia --trace-compile="traced.jl" -e '\
    using Plots; \
    plot(sin); plot(rand(10),rand(10)) |> display; \
    ' && \
    julia -e 'using PackageCompiler; \
              PackageCompiler.create_sysimage(\
                  [\
                    :OhMyREPL, :Revise, :Plots, \
                  ], \
                  precompile_statements_file="traced.jl", \
                  replace_default=true); \
             ' && \
    rm traced.jl

COPY ./.statements /tmp

RUN mkdir -p /sysimages && julia -e '\
    using PackageCompiler; PackageCompiler.create_sysimage(\
        [:Plots, :Juno, :Atom], \
        precompile_statements_file="/tmp/atomcompile.jl", \
        sysimage_path="/sysimages/atom.so", \
    ) \
    '



RUN mkdir -p /sysimages && julia -e '\
    using PackageCompiler; PackageCompiler.create_sysimage(\
        [:IJulia], \
        precompile_statements_file="/tmp/ijuliacompile.jl", \
        sysimage_path="/sysimages/ijulia.so", \
    ) \
    '

COPY ./requirements.txt /work/requirements.txt
RUN pip install -r requirements.txt
COPY ./Project.toml /work/Project.toml

# Initialize Julia package using /work/Project.toml
RUN rm -f Manifest.toml && julia -e 'using Pkg; \
Pkg.instantiate(); \
Pkg.precompile(); \
' && \
# Check Julia version \
julia -e 'using InteractiveUtils; versioninfo()'

# For Jupyter Notebook
EXPOSE 8888
# For Http Server
EXPOSE 8000

CMD ["julia"]