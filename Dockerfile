# Generated by Neurodocker v0.3.2.
#
# Thank you for using Neurodocker. If you discover any issues
# or ways to improve this software, please submit an issue or
# pull request on our GitHub repository:
#     https://github.com/kaczmarj/neurodocker
#
# Timestamp: 2018-02-02 16:32:55

FROM debian:stretch

ARG DEBIAN_FRONTEND=noninteractive

#----------------------------------------------------------
# Install common dependencies and create default entrypoint
#----------------------------------------------------------
# replace shell with bash so we can source files
RUN rm /bin/sh && ln -s /bin/bash /bin/sh

ENV LANG="en_US.UTF-8" \
    LC_ALL="C.UTF-8" \
    ND_ENTRYPOINT="/neurodocker/startup.sh"
RUN apt-get update -qq && apt-get install -yq --no-install-recommends  \
    	apt-utils bzip2 ca-certificates curl locales unzip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    && localedef --force --inputfile=en_US --charmap=UTF-8 C.UTF-8 \
    && chmod 777 /opt && chmod a+s /opt \
    && mkdir -p /neurodocker \
    && if [ ! -f "$ND_ENTRYPOINT" ]; then \
         echo '#!/usr/bin/env bash' >> $ND_ENTRYPOINT \
         && echo 'set +x' >> $ND_ENTRYPOINT \
         && echo 'if [ -z "$*" ]; then /usr/bin/env bash; else $*; fi' >> $ND_ENTRYPOINT; \
       fi \
    && chmod -R 777 /neurodocker && chmod a+s /neurodocker

RUN apt-get update -qq \
    && apt-get install -y -q --no-install-recommends git \
                                                     gcc \
                                                     pigz \
                                                     wget \
                                                     curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# nvm environment variables
ENV NVM_DIR /usr/local/nvm
ENV NODE_VERSION 10.11.0

# install nvm
# https://github.com/creationix/nvm#install-script
RUN curl --silent -o- https://raw.githubusercontent.com/creationix/nvm/v0.31.2/install.sh | bash

# install node and npm
RUN source $NVM_DIR/nvm.sh \
    && nvm install $NODE_VERSION \
    && nvm alias default $NODE_VERSION \
    && nvm use default

# add node and npm to path so the commands are available
ENV NODE_PATH $NVM_DIR/v$NODE_VERSION/lib/node_modules
ENV PATH $NVM_DIR/versions/node/v$NODE_VERSION/bin:$PATH

#------------------
# Install Miniconda
#------------------
ENV CONDA_DIR=/opt/conda \
    PATH=/opt/conda/bin:$PATH
RUN echo "Downloading Miniconda installer ..." \
    && miniconda_installer=/tmp/miniconda.sh \
    && curl -sSL --retry 5 -o $miniconda_installer https://repo.continuum.io/miniconda/Miniconda3-latest-Linux-x86_64.sh \
    && /bin/bash $miniconda_installer -b -p $CONDA_DIR \
    && rm -f $miniconda_installer \
    && conda config --system --prepend channels conda-forge \
    && conda config --system --set auto_update_conda false \
    && conda config --system --set show_channel_urls true \
    && conda clean -tipsy && sync

#-------------------------
# Create conda environment
#-------------------------
COPY ./ /src/bidsconvert/
USER root
RUN chmod 755 -R /src/
RUN conda create -y -q --name neuro python=3 \
                                    traits=4.6.0 \
    && sync && conda clean -tipsy && sync \
    && /bin/bash -c "source activate neuro \
      && pip install /src/bidsconvert[all]" \
    && sync \
    && sed -i '$isource activate neuro' $ND_ENTRYPOINT

#---------------
# BIDS-validator
#---------------
RUN npm install -g bids-validator

#--------------------------------------------------
# Add NeuroDebian repository
# Please note that some packages downloaded through
# NeuroDebian may have restrictive licenses.
#--------------------------------------------------
RUN apt-get update -qq && apt-get install -yq --no-install-recommends dirmngr gnupg \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    && curl -sSL http://neuro.debian.net/lists/stretch.us-nh.full \
    > /etc/apt/sources.list.d/neurodebian.sources.list \
    && curl -sSL https://dl.dropbox.com/s/zxs209o955q6vkg/neurodebian.gpg \
    | apt-key add - \
    && (apt-key adv --refresh-keys --keyserver hkp://pool.sks-keyservers.net:80 0xA5D32F012649A5A9 || true) \
    && apt-get update

# Install NeuroDebian packages
RUN apt-get update -qq && apt-get install -yq --no-install-recommends git-annex-standalone \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

#--------------------
# Download mri_deface
#--------------------
# # Download mri_deface nd additional files from MGH
# ENV DEFACE_DIR /src/deface
# RUN mkdir -p ${DEFACE_DIR}

# RUN wget -N -qO- -O ${DEFACE_DIR}/mri_deface.gz \
#   ftp://surfer.nmr.mgh.harvard.edu/pub/dist/mri_deface/mri_deface-v1.22-Linux64.gz && \
#   gunzip ${DEFACE_DIR}/mri_deface.gz && \
#   chmod +x ${DEFACE_DIR}/mri_deface

# RUN wget -N -qO- -O ${DEFACE_DIR}/face.gca.gz \
#   ftp://surfer.nmr.mgh.harvard.edu/pub/dist/mri_deface/face.gca.gz && \
#   gunzip ${DEFACE_DIR}/face.gca.gz

# RUN wget -N -qO- -O ${DEFACE_DIR}/talairach_mixed_with_skull.gca.gz \
#   ftp://surfer.nmr.mgh.harvard.edu/pub/dist/mri_deface/talairach_mixed_with_skull.gca.gz && \
#   gunzip ${DEFACE_DIR}/talairach_mixed_with_skull.gca.gz

# ENV PATH=$PATH:${DEFACE_DIR}

# Create new user: neuro
RUN useradd --no-user-group --create-home --shell /bin/bash neuro
USER neuro

WORKDIR /home/neuro

#--------------------------------------------
# Set environmental variables for Singularity
#--------------------------------------------
ENV SINGULARITY_CACHEDIR /scratch
ENV SINGULARITY_TMPDIR /scratch

#----------------------
# Set entrypoint script
#----------------------
COPY ./ /scripts/
ENTRYPOINT ["/neurodocker/startup.sh", "bidsify"]
