# Use the official Ubuntu base image
FROM ubuntu:latest

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV MYSQL_ROOT_PASSWORD=admin

# Update the package list and install dependencies
RUN apt-get update && \
    apt-get install -y \
    git \
    software-properties-common \
    mariadb-client \
    redis-server \
    xvfb \
    libfontconfig \
    wkhtmltopdf \
    curl \
    sudo \
    cron \
    nginx \
    supervisor \
    nano \
    wait-for-it \
    jq \
    gettext \
    && apt-get clean

# Install Python 3.10
RUN add-apt-repository ppa:deadsnakes/ppa && \
    apt-get update && \
    apt-get install -y python3.10 python3.10-dev python3.10-venv python3-pip python3-setuptools && \
    apt-get clean

# Clean up
RUN rm -rf /var/lib/apt/lists/* \
&& rm -fr /etc/nginx/sites-enabled/default

# Set python3 to use Python 3.10
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.10 1

# Install Node.js 20.16
RUN curl -sL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs=20.16.0-1nodesource1 && \
    apt-get clean

# Install Yarn
RUN npm install -g yarn

# RUN mysqld_safe --skip-networking & \
#     sleep 5 && \
#     mysqladmin -u root password "${MYSQL_ROOT_PASSWORD}"

# Install Frappe Bench
RUN pip3 install --break-system-packages frappe-bench

#COPY resources/nginx.conf /etc/nginx/conf.d/frappe.conf
COPY resources/supervisor.conf /etc/supervisor/conf.d/frappe.conf

# Create a user for Frappe Bench
RUN useradd -m -s /bin/bash frappe && \
    usermod -aG sudo frappe

# Set the password for the frappe user
RUN echo 'frappe:frappe' | chpasswd

# Add the frappe user to the sudoers file
RUN echo 'frappe ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# Fixes for non-root nginx and logs to stdout
RUN sed -i '/user www-data/d' /etc/nginx/nginx.conf \
&& ln -sf /dev/stdout /var/log/nginx/access.log && ln -sf /dev/stderr /var/log/nginx/error.log \
&& touch /run/nginx.pid \
&& chown -R frappe:frappe /etc/nginx/conf.d \
&& chown -R frappe:frappe /etc/nginx/nginx.conf \
&& chown -R frappe:frappe /var/log/nginx \
&& chown -R frappe:frappe /var/lib/nginx \
&& chown -R frappe:frappe /run/nginx.pid \
&& chown -R frappe:frappe /etc/supervisor/conf.d \
&& chown -R frappe:frappe /etc/supervisor/supervisord.conf \
&& chown -R frappe:frappe /var/log/supervisor

COPY resources/nginx-template.conf /templates/nginx/frappe.conf.template
COPY resources/nginx-entrypoint.sh /usr/local/bin/nginx-entrypoint.sh
RUN chmod +x /usr/local/bin/nginx-entrypoint.sh


# Switch to the frappe user
USER frappe
WORKDIR /home/frappe

ARG FRAPPE_BRANCH=version-14
ARG FRAPPE_PATH=https://github.com/metactical/frappe.git
ARG ERPNEXT_REPO=https://github.com/metactical/erpnext.git
ARG ERPNEXT_BRANCH=version-14

# Verify repository URL and branch
RUN git ls-remote --heads ${FRAPPE_PATH} ${FRAPPE_BRANCH} && \
  git ls-remote --heads ${ERPNEXT_REPO} ${ERPNEXT_BRANCH}

RUN bench init \
  --frappe-branch=${FRAPPE_BRANCH} \
  --frappe-path=${FRAPPE_PATH} \
  /home/frappe/frappe-bench && \
  cd /home/frappe/frappe-bench && \
  bench get-app --branch=${ERPNEXT_BRANCH} --resolve-deps erpnext ${ERPNEXT_REPO} && \
  bench get-app --branch version-14 hrms https://github.com/metactical/hrms.git 

# Set working directory
WORKDIR /home/frappe/frappe-bench

# Install Metactical
RUN bench get-app --branch version-14 metactical https://github.com/metactical/metactical.git
RUN cd /home/frappe/frappe-bench/apps/metactical && \
  git config remote.upstream.fetch "+refs/heads/*:refs/remotes/upstream/*"


# Expose necessary ports
EXPOSE 80 8000 9000

VOLUME [ \
  "/home/frappe/frappe-bench/sites", \
  "/home/frappe/frappe-bench/sites/assets", \
  "/home/frappe/frappe-bench/logs" \
]