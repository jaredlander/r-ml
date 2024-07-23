ARG BASE_IMAGE=rocker/geospatial
ARG R_MAJOR=4
ARG R_MINOR=4
ARG R_PATCH=0
ARG CUDA_MAJOR=11
ARG CUDA_MINOR=8
ARG CUDA_PATCH=0
# since we are using rocker we don't need the CUDNN info anymore but leaving for now
ARG CUDNN_VERSION=8
ARG CUDNN_TYPE=runtime
# since we are using rocker we don't need the distro info anymore but leaving for now
ARG DISTRO_NAME=ubuntu
ARG DISTRO_VERSION=22.04

ARG NCPUS=-1

ARG COMPUTE_TYPE=cpu

FROM ${BASE_IMAGE}:${R_MAJOR}.${R_MINOR}.${R_PATCH} AS base

# renews the R_VER and BASE_IMAGE args
ARG BASE_IMAGE
ARG R_MAJOR
ARG R_MINOR
ARG R_PATCH
ARG CUDA_MAJOR
ARG CUDA_MINOR
ARG CUDA_PATCH
# since we are using rocker we don't need the CUDNN info anymore but leaving for now
ARG CUDNN_VERSION
ARG CUDNN_TYPE
# since we are using rocker we don't need the distro info anymore but leaving for now
ARG DISTRO_NAME
ARG DISTRO_VERSION

ARG NCPUS
ENV NCPUS=${NCPUS}

ARG COMPUTE_TYPE
ENV COMPUTE_TYPE=${COMPUTE_TYPE}

ARG IMAGE_NAME=workshop
LABEL Name=${IMAGE_NAME} Version=R${R_MAJOR}.${R_MINOR}.${R_PATCH} authors="Jared P. Lander"

# update apt packages and install pip so we can install radian
RUN apt update \
    # && apt upgrade -y \
    && apt install -y python3-pip \
    tmux \
    && rm -rf /var/lib/apt/lists/* \
    && pip3 install radian

# install zellij so we can have terminal multiplexing
# I prefer this over tmux
# but it gives problems on the first load, so skipping for now
RUN zellij_version=$(wget -q https://github.com/zellij-org/zellij/releases/latest -O - | grep -oE "v[0-9]{1,}\.[0-9]{1,}\.[0-9]{1,}" -m 1) \
    && wget -nv https://github.com/zellij-org/zellij/releases/download/${zellij_version}/zellij-x86_64-unknown-linux-musl.tar.gz -O /tmp/zellij.tar.gz \
    && tar -xvf /tmp/zellij.tar.gz -C /tmp \
    && chmod +x /tmp/zellij \
    && mv /tmp/zellij /usr/local/bin/. \
    && rm -f /tmp/zellij.tar.gz

# write some options to the default .Rprofile
# this could all be done with one echo but this is cleaner
# the first line is from the existing file from rocker, but we're wiping out the file
# this makes things nicer if we're using vscode and not rstudio
# If this image is entended to be run in VS Code, this env var should be set in the image: ENV TERM_PROGRAM=vscode
# but it is better to set that at runtime
RUN echo "options(HTTPUserAgent = sprintf('R/%s R (%s)', getRversion(), paste(getRversion(), R.version['platform'], R.version['arch'], R.version['os'])))" > "${R_HOME}/etc/Rprofile.site" \
    && echo "options(download.file.method = 'libcurl', timeout=600, Ncpus=${NCPUS})" >> "${R_HOME}/etc/Rprofile.site" \
    # this directs renv to use this repo instead of another
    && echo "RENV_CONFIG_REPOS_OVERRIDE=https://packagemanager.posit.co/cran/__linux__/$(lsb_release -cs)/latest" >> "${R_HOME}/etc/Renviron.site" \
    # this part is only needed for vscode
    && echo "if (interactive() && Sys.getenv('TERM_PROGRAM') == 'vscode' && Sys.getenv('RSTUDIO') == '') { \n \
    .initFile <- file.path(Sys.getenv('HOME'), '.vscode-R', 'init.R') \n \
    if(file.exists(.initFile)){ \n \
        source(.initFile) \n \
    } \n \
    options(vsc.rstudioapi = TRUE) \n \
    if ('httpgd' %in% .packages(all.available = TRUE)) { \n\
        options(vsc.plot = FALSE) \n\
        options(device = function(...) { \n\
        httpgd::hgd(silent = TRUE) \n\
        .vsc.browser(httpgd::hgd_url(history = FALSE), viewer = 'Beside') \n\
        }) \n\
    } \n\
    }" >> "${R_HOME}/etc/Rprofile.site"

FROM base as cpu

# this not needed but leaving for testing
# ARG COMPUTE_TYPE
# ENV COMPUTE_TYPE=${COMPUTE_TYPE}
# RUN echo "Type: inside cpu: ${COMPUTE_TYPE}"

# this comes largely from
# https://torch.mlverse.org/docs/articles/installation#pre-built
RUN torch_ver=$(Rscript -e "cat(utils::available.packages(repos='https://packagemanager.posit.co/cran/__linux__/$(lsb_release -cs)/latest')['torch', 'Version'])") \
    && echo "options(repos = c(torch='https://torch-cdn.mlverse.org/packages/cpu/${torch_ver}/', CRAN = 'https://packagemanager.posit.co/cran/__linux__/$(lsb_release -cs)/latest'))" >> "${R_HOME}/etc/Rprofile.site"

# install torch
RUN Rscript -e "install.packages('torch')"
RUN install2.r --repos getOption --skipinstalled --ncpus ${NCPUS} \
    torch \
    && rm -rf /tmp/downloaded_packages

# install xgboost using CRAN
RUN install2.r --repos getOption --skipinstalled --ncpus ${NCPUS} \
    xgboost \
    && rm -rf /tmp/downloaded_packages;

FROM base as gpu

# this not needed but leaving for testing
# ARG COMPUTE_TYPE
# ENV COMPUTE_TYPE=${COMPUTE_TYPE}
# RUN echo "Type: inside gpu: ${COMPUTE_TYPE}"

# this comes largely from
# https://torch.mlverse.org/docs/articles/installation#pre-built
RUN torch_ver=$(Rscript -e "cat(utils::available.packages(repos='https://packagemanager.posit.co/cran/__linux__/$(lsb_release -cs)/latest')['torch', 'Version'])") \
    && echo "options(repos = c(torch='https://torch-cdn.mlverse.org/packages/cu${CUDA_MAJOR}${CUDA_MINOR}/${torch_ver}/', CRAN = 'https://packagemanager.posit.co/cran/__linux__/$(lsb_release -cs)/latest'))" >> "${R_HOME}/etc/Rprofile.site"

# install torch
RUN install2.r --repos getOption --skipinstalled --ncpus ${NCPUS} \
    torch \
    && rm -rf /tmp/downloaded_packages

ARG NVBLAS_CONFIG_FILE="/etc/nvblas.conf"
ENV NVBLAS_CONFIG_FILE ${NVBLAS_CONFIG_FILE:-/etc/nvblas.conf}

# nvblas configuration
RUN touch /var/log/nvblas.log && chown :staff /var/log/nvblas.log \
    && chmod a+rw /var/log/nvblas.log

# Configure R & RStudio to use drop-in CUDA blas
# Allow R to use CUDA for BLAS, with fallback on openblas
# NOTE: NVBLAS_CPU_BLAS_LIB must be correct for UBUNTU_VERSION selected in scripts/install_R.sh#L25
# This isn't working write now, but it's not hurting anything so I'll leave it
# https://github.com/rocker-org/rocker-versioned2/blob/master/scripts/config_R_cuda.sh
RUN echo "NVBLAS_LOGFILE /var/log/nvblas.log" > ${NVBLAS_CONFIG_FILE} \
    && echo "NVBLAS_CPU_BLAS_LIB /usr/lib/x86_64-linux-gnu/openblas-pthread/libblas.so.3" >> ${NVBLAS_CONFIG_FILE} \
    && echo "NVBLAS_GPU_LIST ALL" >> ${NVBLAS_CONFIG_FILE} \
    && echo "NVBLAS_AUTOPIN_MEM_ENABLED" >> ${NVBLAS_CONFIG_FILE} \
    && echo "NVBLAS_CONFIG_FILE=${NVBLAS_CONFIG_FILE}" >> ${R_HOME}/etc/Renviron.site

# install xgboost from the prebuilt GPU binary (https://github.com/dmlc/xgboost/issues/6654)
# the first line finds the right file
RUN wget -nv $(wget -q https://github.com/dmlc/xgboost/releases/latest -O - | grep -oP "https://.+xgboost_r_gpu_linux_\w+\.tar\.gz") -O xgboost.tar.gz \
    # actually install the package
    && R CMD INSTALL ./xgboost.tar.gz \
    # remove the installer
    && rm ./xgboost.tar.gz;
    
FROM ${COMPUTE_TYPE} AS main

# this not needed but leaving for testing
# ARG COMPUTE_TYPE
# ENV COMPUTE_TYPE=${COMPUTE_TYPE}
# RUN echo "Type: inside main: ${COMPUTE_TYPE}"

# install many other R packages we use
RUN install2.r --repos getOption --skipinstalled --ncpus ${NCPUS} \
    # mapping    
    leafem leafgl h3jsr \
    rsgeo sfdep \
    # data manipulation
    arrow \
    duckdb duckplyr \
    dbplyr dtplyr \
    DBI odbc RPostgres pool connections dm \
    # for xgboost
    data.table jsonlite DiagrammeR \
    #common ML packages
    glmnet \ 
    randomForest ranger \
    party partykit rpart.plot \
    pre \
    C50 \
    # tidymodels
    tidymodels themis vetiver \
    coefplot \
    # torch related
    luz zeallot torchvision tok torchexport torchdatasets \
    # LLMs
    ollama \
    # other
    pins \
    plumber \
    tictoc \
    # shiny related
    bs4lib shinyWidgets shinyjs shinyalert rsconnect \
    # nice tables
    kableExtra gt gtsummary reactable reactablefmtr \
    # time series forecasting
    forecast tsibble fable feasts \
    # orchestrating
    targets tarchetypes crew miarai fst qs visNetwork \
    # linear optimization
    ompr ompr.roi ROI \
    ROI.plugin.glpk ROI.plugin.symphony ROI.plugin.lpsolve ROI.plugin.mosek ROI.plugin.nloptr \
    ROI.plugin.optimx ROI.plugin.quadpro \
    # convex optimization
    CVXR Rglpk Rmosek gurobi osqp ECOSolveR \
    quarto \
    # working in VS Code 
    httpgd languageserver \
    # remove the package downloads for a smaller build
    && rm -rf /tmp/downloaded_packages

# install packages from github
RUN Rscript -e "purrr::walk(c('geoarrow/geoarrow-r', 'calderonsamuel/ollama', 'mlverse/chattr', 'JosiahParry/h3o'), remotes::install_github)"

# Use some nice config settings
# we also want these to be mountable
# so we will figure out volumes for this file and similar ones
COPY ./config/rstudio-prefs.json /home/${USER:-rstudio}/.config/rstudio/rstudio-prefs.json

# this not needed but leaving for testing
# RUN echo "Type: at end: ${COMPUTE_TYPE}"
