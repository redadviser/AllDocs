# Dockerfile para backend Node.js/TypeScript
FROM node:18-alpine

# Define diretório de trabalho
WORKDIR /app

# Copia package.json e package-lock.json
COPY package.json package-lock.json ./

# Instala dependências
RUN npm ci

# Copia o restante do código
COPY . .

# Compila TypeScript
RUN npm run build

# Expõe porta padrão
EXPOSE 3000

# Inicializa o backend
CMD ["node", "dist/main.js"]
