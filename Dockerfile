# Builder Stage
FROM alpine:3.16 as builder

# Install necessary packagess
RUN apk add --no-cache wget unzip curl python3 py3-pip

# Install Terraform
RUN wget https://releases.hashicorp.com/terraform/1.8.2/terraform_1.8.2_linux_amd64.zip \
    && unzip terraform_1.8.2_linux_amd64.zip -d /usr/local/bin \
    && rm terraform_1.8.2_linux_amd64.zip

# Install AWS CLI
RUN wget https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -O awscliv2.zip \
    && unzip awscliv2.zip \
    && ./aws/install -i /usr/local/aws-cli -b /usr/local/bin \
    && rm -rf awscliv2.zip ./aws

WORKDIR /work/
COPY app/ .
RUN pip3 install --no-cache-dir -r requirements.txt

RUN mkdir aws

# Final Stage
FROM alpine:3.16

COPY --from=builder /usr/local/bin/terraform /usr/local/bin/
COPY --from=builder /usr/local/bin/aws /usr/local/bin/
COPY --from=builder /work /work

ARG AWS_ACCESS_KEY_ID
ARG AWS_SECRET_ACCESS_KEY
ARG AWS_DEFAULT_REGION

RUN echo "[default]" >> aws/credentials
RUN echo "aws_access_key_id = $(echo $AWS_ACCESS_KEY_ID)" >> aws/credentials 
RUN echo "aws_secret_access_key = $(echo $AWS_SECRET_ACCESS_KEY)" >> aws/credentials

WORKDIR /work

# Install runtime dependencies
RUN apk add --no-cache python3 py3-pip \
    && pip3 install --no-cache-dir -r requirements.txt

EXPOSE 8080

CMD ["python3", "app.py"]
