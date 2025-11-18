from flask import Flask, render_template, request, redirect, url_for, flash, jsonify
from datetime import datetime, date
from decimal import Decimal
from models import db, Usuario, Autor, Livro, Cliente, Venda, VendaItem, livro_autor
from config import Config
from flask_login import LoginManager, login_user, logout_user, login_required, current_user
from flask_wtf.csrf import CSRFProtect
import os

from flask_limiter import Limiter
from flask_limiter.util import get_remote_address

app = Flask(__name__)
app.config.from_object(Config)
csrf = CSRFProtect()
csrf.init_app(app)

# ✅ CORREÇÃO DO LIMITER - Opção 1 (Recomendada)
limiter = Limiter(app=app, key_func=get_remote_address)

db.init_app(app)

# Configuração do Flask-Login
login_manager = LoginManager()
login_manager.init_app(app)
login_manager.login_view = 'login'
login_manager.login_message = 'Por favor, faça login para acessar esta página.'
login_manager.login_message_category = 'info'

@login_manager.user_loader
def load_user(user_id):
    return Usuario.query.get(int(user_id))

def criar_usuarios_iniciais():
    with app.app_context():
        if Usuario.query.count() == 0:
            try:
                # Criar usuário admin
                admin = Usuario(
                    username='admin',
                    email='admin@editora.com',
                    is_admin=True
                )
                admin.set_password('admin123')
                db.session.add(admin)
                
                # Criar usuário regular
                usuario = Usuario(
                    username='usuario',
                    email='usuario@editora.com', 
                    is_admin=False
                )
                usuario.set_password('senha123')
                db.session.add(usuario)
                
                db.session.commit()
                print("Usuários iniciais criados:")
                print("Admin: admin / admin123")
                print("Usuário: usuario / senha123")
                
            except Exception as e:
                db.session.rollback()
                print(f"Erro ao criar usuários: {e}")

with app.app_context():
    db.create_all()
    criar_usuarios_iniciais()

# ===== ROTAS DE AUTENTICAÇÃO =====

@app.route('/login', methods=['GET', 'POST'])
@limiter.limit("5 per minute")  # Máximo 5 tentativas por minuto
def login():
    """Página de login"""
    if current_user.is_authenticated:
        return redirect(url_for('index'))
    
    if request.method == 'POST':
        username = request.form.get('username')
        password = request.form.get('password')
        remember = bool(request.form.get('remember'))
        
        usuario = Usuario.query.filter_by(username=username).first()
        
        if usuario and usuario.check_password(password):
            login_user(usuario, remember=remember)
            flash(f'Bem-vindo, {usuario.username}!', 'success')
            return redirect(url_for('index'))
        else:
            flash('Usuário ou senha incorretos', 'error')
    
    return render_template('login.html')

@app.route('/logout', methods=['POST'])
@login_required
def logout():
    """Logout do usuário"""
    username = current_user.username
    logout_user()
    flash(f'Até logo, {username}! Você foi desconectado com sucesso.', 'info')
    return redirect(url_for('login'))

@app.route('/registro', methods=['GET', 'POST'])
@limiter.limit("3 per minute")  # Adicionei rate limiting aqui também
def registro():
    """Página de registro de novos usuários"""
    if current_user.is_authenticated:
        return redirect(url_for('index'))
    
    if request.method == 'POST':
        username = request.form.get('username')
        email = request.form.get('email')
        password = request.form.get('password')
        confirm_password = request.form.get('confirm_password')
        
        # Validações
        if not username or not email or not password:
            flash('Todos os campos são obrigatórios', 'error')
            return redirect(url_for('registro'))
        
        if password != confirm_password:
            flash('As senhas não coincidem', 'error')
            return redirect(url_for('registro'))
        
        if Usuario.query.filter_by(username=username).first():
            flash('Nome de usuário já existe', 'error')
            return redirect(url_for('registro'))
        
        if Usuario.query.filter_by(email=email).first():
            flash('Email já cadastrado', 'error')
            return redirect(url_for('registro'))
        
        # Criar novo usuário
        novo_usuario = Usuario(
            username=username,
            email=email,
            is_admin=False
        )
        novo_usuario.set_password(password)
        
        db.session.add(novo_usuario)
        db.session.commit()
        
        flash('Conta criada com sucesso! Faça login para continuar.', 'success')
        return redirect(url_for('login'))
    
    return render_template('registro.html')

# ===== ROTA DE TESTE DO LIMITER =====
@app.route('/teste-limite')
@limiter.limit("3 per minute")
def teste_limite():
    """Rota para testar se o rate limiting está funcionando"""
    return jsonify({
        "message": "✅ Limiter funcionando!",
        "timestamp": datetime.utcnow().isoformat(),
        "seu_ip": request.remote_addr,
        "tentativas_restantes": "3 por minuto"
    })

# ===== MIDDLEWARE PARA DEBUG =====
@app.after_request
def after_request(response):
    """Middleware para debug do limiter"""
    if response.status_code == 429:
        print(f"🚫 RATE LIMIT ATINGIDO! IP: {request.remote_addr}")
        print(f"📊 Path: {request.path}")
    
    # Log básico de todas as requisições
    print(f"📨 {request.method} {request.path} - {response.status_code} - IP: {request.remote_addr}")
    
    return response
# ===== ROTAS PROTEGIDAS =====
@app.route('/')
@login_required
def index():
    """Página inicial com estatísticas"""
    total_autores = Autor.query.count()
    total_livros = Livro.query.count()
    total_clientes = Cliente.query.count()
    total_vendas = db.session.query(db.func.sum(Venda.valor_total)).scalar() or 0
    
    return render_template('index.html',
        total_autores=total_autores,
        total_livros=total_livros,
        total_clientes=total_clientes,
        total_vendas=total_vendas
    )

# ===== ROTAS AUTORES =====
@app.route('/autores')
@login_required
def listar_autores():
    """Lista todos os autores com paginação"""
    pagina = request.args.get('pagina', 1, type=int)
    por_pagina = request.args.get('por_pagina', 10, type=int)
    
    autores = Autor.query.paginate(
        page=pagina, 
        per_page=por_pagina, 
        error_out=False
    )
    return render_template('autores.html', autores=autores)

@app.route('/autores/novo', methods=['GET', 'POST'])
@login_required
def novo_autor():
    """Criar novo autor"""
    if request.method == 'POST':
        nome = request.form.get('nome')
        data_nascimento = request.form.get('data_nascimento')
        nacionalidade = request.form.get('nacionalidade')
        
        if not nome:
            flash('Nome é obrigatório', 'error')
            return redirect(url_for('novo_autor'))
        
        autor = Autor(
            nome=nome,
            data_nascimento=datetime.strptime(data_nascimento, '%Y-%m-%d').date() if data_nascimento else None,
            nacionalidade=nacionalidade
        )
        db.session.add(autor)
        db.session.commit()
        flash(f'Autor {nome} criado com sucesso!', 'success')
        return redirect(url_for('listar_autores'))
    
    return render_template('novo_autor.html')

@app.route('/autores/<int:id>/editar', methods=['GET', 'POST'])
@login_required
def editar_autor(id):
    """Editar autor existente"""
    autor = Autor.query.get_or_404(id)
    if request.method == 'POST':
        autor.nome = request.form.get('nome')
        data_nascimento = request.form.get('data_nascimento')
        autor.data_nascimento = datetime.strptime(data_nascimento, '%Y-%m-%d').date() if data_nascimento else None
        autor.nacionalidade = request.form.get('nacionalidade')
        
        db.session.commit()
        flash('Autor atualizado com sucesso!', 'success')
        return redirect(url_for('listar_autores'))
    
    return render_template('editar_autor.html', autor=autor)

@app.route('/autores/<int:id>/deletar', methods=['POST'])
@login_required
def deletar_autor(id):
    """Deletar autor"""
    autor = Autor.query.get_or_404(id)
    db.session.delete(autor)
    db.session.commit()
    flash('Autor deletado com sucesso!', 'success')
    return redirect(url_for('listar_autores'))

# ===== ROTAS LIVROS =====
@app.route('/livros')
@login_required
def listar_livros():
    """Lista todos os livros com paginação"""
    pagina = request.args.get('pagina', 1, type=int)
    por_pagina = request.args.get('por_pagina', 10, type=int)
    
    livros = Livro.query.paginate(
        page=pagina, 
        per_page=por_pagina, 
        error_out=False
    )
    return render_template('livros.html', livros=livros)

@app.route('/livros/novo', methods=['GET', 'POST'])
@login_required
def novo_livro():
    """Criar novo livro"""
    try:
        if request.method == 'POST':
            titulo = request.form.get('titulo')
            isbn = request.form.get('isbn')
            data_publicacao = request.form.get('data_publicacao')
            genero = request.form.get('genero')
            autores_ids = request.form.getlist('autores')
            
            if not titulo or not isbn:
                flash('Título e ISBN são obrigatórios', 'error')
                return redirect(url_for('novo_livro'))
            
            # Tratamento para data vazia
            data_publicacao_obj = None
            if data_publicacao:
                try:
                    data_publicacao_obj = datetime.strptime(data_publicacao, '%Y-%m-%d').date()
                except ValueError:
                    flash('Formato de data inválido', 'error')
                    return redirect(url_for('novo_livro'))
            
            livro = Livro(
                titulo=titulo,
                isbn=isbn,
                data_publicacao=data_publicacao_obj,
                genero=genero
            )
            
            for autor_id in autores_ids:
                autor = Autor.query.get(autor_id)
                if autor:
                    livro.autores.append(autor)
            
            db.session.add(livro)
            db.session.commit()
            flash(f'Livro {titulo} criado com sucesso!', 'success')
            return redirect(url_for('listar_livros'))
        
        autores = Autor.query.all()
        return render_template('novo_livro.html', autores=autores)
    
    except Exception as e:
        print(f"Erro: {e}")
        flash(f'Erro ao processar a requisição: {str(e)}', 'error')
        return redirect(url_for('listar_livros'))

@app.route('/livros/<int:id>/editar', methods=['GET', 'POST'])
@login_required
def editar_livro(id):
    """Editar livro existente"""
    livro = Livro.query.get_or_404(id)
    if request.method == 'POST':
        livro.titulo = request.form.get('titulo')
        livro.isbn = request.form.get('isbn')
        data_publicacao = request.form.get('data_publicacao')
        livro.data_publicacao = datetime.strptime(data_publicacao, '%Y-%m-%d').date() if data_publicacao else None
        livro.genero = request.form.get('genero')
        
        livro.autores.clear()
        autores_ids = request.form.getlist('autores')
        for autor_id in autores_ids:
            autor = Autor.query.get(autor_id)
            if autor:
                livro.autores.append(autor)
        
        db.session.commit()
        flash('Livro atualizado com sucesso!', 'success')
        return redirect(url_for('listar_livros'))
    
    autores = Autor.query.all()
    return render_template('editar_livro.html', livro=livro, autores=autores)

@app.route('/livros/<int:id>/deletar', methods=['POST'])
@login_required
def deletar_livro(id):
    """Deletar livro"""
    livro = Livro.query.get_or_404(id)
    db.session.delete(livro)
    db.session.commit()
    flash('Livro deletado com sucesso!', 'success')
    return redirect(url_for('listar_livros'))

# ===== ROTAS CLIENTES =====
@app.route('/clientes')
@login_required
def listar_clientes():
    """Lista todos os clientes com paginação"""
    pagina = request.args.get('pagina', 1, type=int)
    por_pagina = request.args.get('por_pagina', 10, type=int)
    
    clientes = Cliente.query.paginate(
        page=pagina, 
        per_page=por_pagina, 
        error_out=False
    )
    return render_template('clientes.html', clientes=clientes)

@app.route('/clientes/novo', methods=['GET', 'POST'])
@login_required
def novo_cliente():
    """Criar novo cliente"""
    if request.method == 'POST':
        nome = request.form.get('nome')
        email = request.form.get('email')
        
        if not nome or not email:
            flash('Nome e email são obrigatórios', 'error')
            return redirect(url_for('novo_cliente'))
        
        cliente = Cliente(nome=nome, email=email)
        db.session.add(cliente)
        db.session.commit()
        flash(f'Cliente {nome} criado com sucesso!', 'success')
        return redirect(url_for('listar_clientes'))
    
    return render_template('novo_cliente.html')

@app.route('/clientes/<int:id>/editar', methods=['GET', 'POST'])
@login_required
def editar_cliente(id):
    """Editar cliente existente"""
    cliente = Cliente.query.get_or_404(id)
    if request.method == 'POST':
        cliente.nome = request.form.get('nome')
        cliente.email = request.form.get('email')
        
        db.session.commit()
        flash('Cliente atualizado com sucesso!', 'success')
        return redirect(url_for('listar_clientes'))
    
    return render_template('editar_cliente.html', cliente=cliente)

@app.route('/clientes/<int:id>/deletar', methods=['POST'])
@login_required
def deletar_cliente(id):
    """Deletar cliente"""
    cliente = Cliente.query.get_or_404(id)
    db.session.delete(cliente)
    db.session.commit()
    flash('Cliente deletado com sucesso!', 'success')
    return redirect(url_for('listar_clientes'))

# ===== ROTAS VENDAS =====
@app.route('/vendas')
@login_required
def listar_vendas():
    """Lista todas as vendas com paginação"""
    pagina = request.args.get('pagina', 1, type=int)
    por_pagina = request.args.get('por_pagina', 10, type=int)
    
    vendas = Venda.query.paginate(
        page=pagina, 
        per_page=por_pagina, 
        error_out=False
    )
    return render_template('vendas.html', vendas=vendas)

@app.route('/vendas/nova', methods=['GET', 'POST'])
@login_required
def nova_venda():
    """Criar nova venda"""
    if request.method == 'POST':
        cliente_id = request.form.get('cliente_id')
        data_venda = request.form.get('data_venda')
        
        if not cliente_id or not data_venda:
            flash('Cliente e data são obrigatórios', 'error')
            return redirect(url_for('nova_venda'))
        
        venda = Venda(
            cliente_id=cliente_id,
            data_venda=datetime.strptime(data_venda, '%Y-%m-%d').date()
        )
        
        livro_ids = request.form.getlist('livro_id')
        quantidades = request.form.getlist('quantidade')
        precos = request.form.getlist('preco')
        
        valor_total = Decimal('0')
        for livro_id, quantidade, preco in zip(livro_ids, quantidades, precos):
            if livro_id and quantidade and preco:
                item = VendaItem(
                    livro_id=livro_id,
                    quantidade=int(quantidade),
                    preco_unitario=Decimal(preco)
                )
                venda.itens.append(item)
                valor_total += Decimal(quantidade) * Decimal(preco)
        
        venda.valor_total = valor_total
        db.session.add(venda)
        db.session.commit()
        flash('Venda criada com sucesso!', 'success')
        return redirect(url_for('listar_vendas'))
    
    clientes = Cliente.query.all()
    livros = Livro.query.all()
    return render_template('nova_venda.html', clientes=clientes, livros=livros)

@app.route('/vendas/<int:id>/deletar', methods=['POST'])
@login_required
def deletar_venda(id):
    """Deletar venda"""
    venda = Venda.query.get_or_404(id)
    db.session.delete(venda)
    db.session.commit()
    flash('Venda deletada com sucesso!', 'success')
    return redirect(url_for('listar_vendas'))

# ===== ROTA PARA PERFIL DO USUÁRIO =====
@app.route('/perfil')
@login_required
def perfil():
    """Página de perfil do usuário"""
    return render_template('perfil.html', usuario=current_user)

# ===== MANIPULADOR DE ERRO 401 =====
@app.errorhandler(401)
def unauthorized_error(error):
    flash('Você precisa fazer login para acessar esta página.', 'error')
    return redirect(url_for('login'))

from flask import render_template

# ===== MANIPULADORES DE ERRO =====
@app.errorhandler(429)
def too_many_requests(error):
    """Página personalizada para erro 429 - Too Many Requests"""
    # Extrai informações do erro
    retry_after = getattr(error, 'retry_after', 60)  # Default 60 segundos
    limit = getattr(error, 'description', 'Limite excedido')
    
    # Log do erro
    print(f"Rate Limit Atingido - IP: {request.remote_addr} - Path: {request.path}")
    
    return render_template('429.html', 
                         retry_after=retry_after,
                         limit=limit), 429

@app.errorhandler(404)
def not_found_error(error):
    return render_template('404.html'), 404

@app.errorhandler(500)
def internal_error(error):
    db.session.rollback()
    return render_template('500.html'), 500


if __name__ == '__main__':
    print(" Servidor iniciado!")
    print(" Rate Limiter ativado nas rotas:")
    print("   - /login: 5 tentativas por minuto")
    print("   - /registro: 3 registros por minuto") 
    print("   - /teste-limite: 3 acessos por minuto")
    print(" Acesse http://127.0.0.1:5000/teste-limite para testar")
    app.run(debug=True, host='0.0.0.0', port=5000)