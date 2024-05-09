FROM alpine:latest as builder

# Instalando dependências
RUN apk add --no-cache wget unzip curl build-base libffi-dev openssl-dev

# Instalando Terraform
RUN wget https://releases.hashicorp.com/terraform/1.8.2/terraform_1.8.2_linux_amd64.zip && \
    unzip terraform_1.8.2_linux_amd64.zip && \
    mv terraform /usr/local/bin/ && \
    rm terraform_1.8.2_linux_amd64.zip

# Configurando diretório de trabalho
WORKDIR /work

# STAGE 2: Final
FROM alpine:latest

WORKDIR /work

COPY app/ .

# Copiando binários e arquivos da STAGE 1
COPY --from=builder /usr/local/bin/terraform /usr/local/bin/terraform
COPY --from=builder /work /work

RUN apk add --no-cache aws-cli

RUN apk add --no-cache python3 py3-pip

# Copiando credenciais da AWS
ARG AWS_ACCESS_KEY_ID
ARG AWS_SECRET_ACCESS_KEY
ARG AWS_DEFAULT_REGION
ARG AWS_SESSION_TOKEN

RUN mkdir aws
RUN touch aws/credentials
RUN echo "[default]" >> aws/credentials && \
    echo "aws_access_key_id = $AWS_ACCESS_KEY_ID" >> aws/credentials && \
    echo "aws_secret_access_key = $AWS_SECRET_ACCESS_KEY" >> aws/credentials && \
    echo "aws_session_token = $AWS_SESSION_TOKEN" >> aws/credentials

# Instalando dependências Python
RUN apk add --no-cache python3 py3-pip

RUN pip3 install --no-cache-dir --user --break-system-packages -r requirements.txt

RUN terraform init

# Configurando o diretório de trabalho


# Expondo a porta 8080
EXPOSE 8080

# Executando a aplicação
CMD ["python3", "app.py"]

CICD COMPLETO:

name: senai_automacao
run-name: ${{ github.actor }} Pipeline deploy
on:
  push:
    branches:
      - "main"
    paths-ignore:
      - "*.txt"
jobs:
  githubactions-senai:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      - name: INSTALL PACKAGES
        run: |
          sudo apt update -y
          sudo apt-get install figlet unzip -y

          curl https://static.snyk.io/cli/latest/snyk-linux -o snyk
          chmod +x ./snyk
          mv ./snyk /usr/local/bin/

          sudo apt-get update && sudo apt-get install -y gnupg software-properties-common
          wget -O- https://apt.releases.hashicorp.com/gpg | \
            gpg --dearmor | \
            sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
         
          echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
            https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
            sudo tee /etc/apt/sources.list.d/hashicorp.list

          sudo apt update -y

          sudo apt-get install terraform -y

      - name: SNYK AUTH
        run : |
          snyk -d auth $SNYK_TOKEN
        env:
          SNYK_TOKEN: ${{ secrets.SNYK_AUTH_TOKEN }}
      - name: Configure AWS CLI
        if: always()
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-session-token: ${{ secrets.AWS_SESSION_TOKEN }}
          aws-region: us-east-1

      - name: Test aws cli
        if: always()
        run: aws sts get-caller-identity

      - name: Docker Login
        if: always()
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ secrets.DOCKER_USER }}
          password: ${{ secrets.DOCKER_PASSWORD }}
     
      - name: Docker build (CI)
        if: always()
        run: |
          docker build --build-arg AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN --build-arg AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID --build-arg AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY --build-arg AWS_DEFAULT_REGION="us-east-1" -t apicontainer .
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          AWS_SESSION_TOKEN: ${{ secrets.AWS_SESSION_TOKEN }}
         
      - name: Docker Analysis (CI)
        if: always()
        run: |
          echo "VULNERABILIDADES" | figlet -c -f small
          snyk container test apicontainer:latest || true
         
      - name: Docker Push (CD)
        if: always()
        run: |
          COMMIT_SHA=$(echo $GITHUB_SHA | cut -c 1-5)
          echo $COMMIT_SHA
          docker tag apicontainer:latest <substituir_aqui>/apicontainer:$COMMIT_SHA
          docker push <substituir_aqui>/apicontainer:$COMMIT_SHA
     
      - name: Terraform Apply
        if: always()
        run: |
          COMMIT_SHA=$(echo $GITHUB_SHA | cut -c 1-5)
          terraform init
          terraform apply -var="github_sha=$COMMIT_SHA" --auto-approve
        env:
          GITHUB_SHA: ${{ github.sha }}
