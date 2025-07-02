#!/bin/bash

set -e

run_or_fail() {
    echo "⚙️ Executando: $1"
    eval "$1" || { echo "❌ Erro ao executar: $1"; exit 1; }
}

wait_for_container() {
    local container=$1
    echo "⏳ Aguardando container '$container' estar pronto..."
    while true; do
        if docker-compose exec -T "$container" echo "✅ $container pronto" &>/dev/null; then
            echo "✅ Container '$container' está pronto!"
            return 0
        fi
        sleep 3
    done
}

kill_port() {
    local port=$1
    echo "🔧 Tentando liberar porta $port (se necessário)..."

    # Primeiro tenta com lsof
    lsof -ti tcp:$port | xargs -r kill -9 || true

    # Depois tenta com fuser, caso o lsof não funcione
    fuser -k ${port}/tcp || true
}

echo "🔪 Finalizando processos que podem estar usando as portas necessárias..."
kill_port 8000   # Django
kill_port 3000   # Next.js
kill_port 3001   # Precaução, caso Next tenha usado
kill_port 3002   # Precaução, caso Next tenha usado

echo "🔧 Subindo containers..."
docker-compose up -d --build

wait_for_container django

echo "📦 Instalando dependências do Django..."
docker-compose exec -T django bash -c "
command -v pipenv >/dev/null 2>&1 || (echo '⚙️ Instalando pipenv...' && pip install pipenv)
pipenv install
"

echo "🔎 Verificando migrações pendentes..."
MIGRATIONS_PENDING=$(docker-compose exec -T django bash -c 'pipenv run python manage.py showmigrations | grep "\[ \]"' | wc -l)

if [ "$MIGRATIONS_PENDING" -gt 0 ]; then
    echo "⚒️ Migrações pendentes detectadas, aplicando..."
    run_or_fail "docker-compose exec -T django bash -c 'pipenv run python manage.py migrate'"
else
    echo "✅ Nenhuma migração pendente"
fi

echo "👤 Garantindo superusuário Django..."
docker-compose exec -T django bash -c "
pipenv run python manage.py shell -c \"
from django.contrib.auth import get_user_model;
User = get_user_model();
if not User.objects.filter(email='admin@user.com').exists():
    User.objects.create_superuser('admin1', 'admin@user.com', 'secret')
\"
"

wait_for_container go_app_dev
wait_for_container nextjs

echo "🎬 Iniciando consumidor Django - Upload Chunks (em background)..."
docker-compose exec -T django bash -c "pipenv run python manage.py consumer_upload_chunks_to_external_storage" &

echo "📡 Iniciando consumidor Django - Registro Processamento (em background)..."
docker-compose exec -T django bash -c "pipenv run python manage.py consumer_register_processed_video_path" &

sleep 5

echo ""
echo "✅ Ambiente pronto! Logs a seguir:"
echo ""

docker-compose logs -f django go_app_dev nextjs


# #!/bin/bash

# set -e

# run_or_fail() {
#     echo "⚙️ Executando: $1"
#     eval "$1" || { echo "❌ Erro ao executar: $1"; exit 1; }
# }

# wait_for_container() {
#     local container=$1
#     echo "⏳ Aguardando container '$container' estar pronto..."
#     for i in {1..10}; do
#         if docker compose exec -T "$container" echo "✅ $container pronto" &>/dev/null; then
#             return 0
#         fi
#         sleep 3
#     done
#     echo "❌ Timeout: container '$container' não respondeu"
#     exit 1
# }

# kill_port() {
#     local port=$1
#     echo "🔧 Tentando liberar porta $port (se necessário)..."

#     # Primeiro tenta com lsof
#     lsof -ti tcp:$port | xargs -r kill -9 || true

#     # Depois tenta com fuser, caso o lsof não funcione
#     fuser -k ${port}/tcp || true
# }

# echo "🔪 Finalizando processos que podem estar usando as portas necessárias..."
# kill_port 8000   # Django
# kill_port 3000   # Next.js
# kill_port 3001   # Precaução, caso Next tenha usado
# kill_port 3002   # Precaução, caso Next tenha usado

# echo "🔧 Subindo containers..."
# docker compose up -d --build

# wait_for_container django

# echo "📦 Instalando dependências do Django..."
# docker compose exec -T django bash -c "
# command -v pipenv >/dev/null 2>&1 || (echo '⚙️ Instalando pipenv...' && pip install pipenv)
# pipenv install
# "

# echo "🔎 Verificando migrações pendentes..."
# MIGRATIONS_PENDING=$(docker compose exec -T django bash -c 'pipenv run python manage.py showmigrations | grep "\[ \]"' | wc -l)

# if [ "$MIGRATIONS_PENDING" -gt 0 ]; then
#     echo "⚒️ Migrações pendentes detectadas, aplicando..."
#     run_or_fail "docker compose exec -T django bash -c 'pipenv run python manage.py migrate'"
# else
#     echo "✅ Nenhuma migração pendente"
# fi

# echo "👤 Garantindo superusuário Django..."
# docker compose exec -T django bash -c "
# pipenv run python manage.py shell -c \"
# from django.contrib.auth import get_user_model;
# User = get_user_model();
# if not User.objects.filter(email='admin@user.com').exists():
#     User.objects.create_superuser('admin1', 'admin@user.com', 'secret')
# \"
# "

# wait_for_container go_app_dev
# wait_for_container nextjs


# echo "🎬 Iniciando consumidor Django - Upload Chunks (em foreground)..."
# docker compose exec -T django bash -c "pipenv run python manage.py consumer_upload_chunks_to_external_storage" &

# echo "📡 Iniciando consumidor Django - Registro Processamento (em foreground)..."
# docker compose exec -T django bash  -c "pipenv run python manage.py  consumer_register_processed_video_path" &
# # echo "iniciando o next... - RegistroProcessamento (em foreground)..." 

# docker compose logs -f django go_app_dev nextjs
