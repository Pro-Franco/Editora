from flask_sqlalchemy import SQLAlchemy
from flask_login import UserMixin
from werkzeug.security import generate_password_hash, check_password_hash
from datetime import datetime

db = SQLAlchemy()

class Usuario(db.Model, UserMixin):
    __tablename__ = 'usuarios'
    
    usuario_id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True, nullable=False, index=True)
    email = db.Column(db.String(120), unique=True, nullable=False, index=True)
    password_hash = db.Column(db.String(255), nullable=False)  # Aumentado para 255
    is_admin = db.Column(db.Boolean, default=False)
    is_active = db.Column(db.Boolean, default=True)
    data_criacao = db.Column(db.DateTime, default=datetime.utcnow)
    data_ultimo_login = db.Column(db.DateTime, nullable=True)

    def get_id(self):
        return str(self.usuario_id)

    def set_password(self, password):
        self.password_hash = generate_password_hash(password)

    def check_password(self, password):
        return check_password_hash(self.password_hash, password)

    def update_last_login(self):
        self.data_ultimo_login = datetime.utcnow()
        db.session.commit()

    def to_dict(self):
        return {
            'usuario_id': self.usuario_id,
            'username': self.username,
            'email': self.email,
            'is_admin': self.is_admin,
            'is_active': self.is_active,
            'data_criacao': self.data_criacao.isoformat() if self.data_criacao else None,
            'data_ultimo_login': self.data_ultimo_login.isoformat() if self.data_ultimo_login else None
        }

    def __repr__(self):
        return f'<Usuario {self.username}>'

# Mantenha os outros modelos (Autor, Livro, Cliente, etc.) como estão
class Autor(db.Model):
    __tablename__ = 'autores'
    autor_id = db.Column(db.Integer, primary_key=True)
    nome = db.Column(db.String(100), nullable=False)
    data_nascimento = db.Column(db.Date)
    nacionalidade = db.Column(db.String(50))
    livros = db.relationship('Livro', secondary='livro_autor', back_populates='autores')

class Livro(db.Model):
    __tablename__ = 'livros'
    livro_id = db.Column(db.Integer, primary_key=True)
    titulo = db.Column(db.String(200), nullable=False)
    isbn = db.Column(db.String(20), unique=True, nullable=False)
    data_publicacao = db.Column(db.Date)
    genero = db.Column(db.String(50))
    autores = db.relationship('Autor', secondary='livro_autor', back_populates='livros')
    vendas_itens = db.relationship('VendaItem', back_populates='livro')

'''class Cliente(db.Model):
    __tablename__ = 'clientes'
    cliente_id = db.Column(db.Integer, primary_key=True)
    nome = db.Column(db.String(100), nullable=False)
    email = db.Column(db.String(120), unique=True, nullable=False)
    vendas = db.relationship('Venda', back_populates='cliente')
'''    
class Cliente(db.Model):
    __tablename__ = 'clientes'
    
    cliente_id = db.Column(db.Integer, primary_key=True)
    nome = db.Column(db.String(100), nullable=False)
    email = db.Column(db.String(120), unique=True, nullable=False)
    data_cadastro = db.Column(db.DateTime, default=datetime.utcnow)  # Adicione esta linha
    
    # Relacionamento com vendas
    vendas = db.relationship('Venda', back_populates='cliente')
    
    def __repr__(self):
        return f'<Cliente {self.nome}>'

class Venda(db.Model):
    __tablename__ = 'vendas'
    venda_id = db.Column(db.Integer, primary_key=True)
    cliente_id = db.Column(db.Integer, db.ForeignKey('clientes.cliente_id'), nullable=False)
    data_venda = db.Column(db.Date, nullable=False, default=datetime.utcnow)
    valor_total = db.Column(db.Numeric(10, 2), nullable=False, default=0)
    cliente = db.relationship('Cliente', back_populates='vendas')
    itens = db.relationship('VendaItem', back_populates='venda', cascade='all, delete-orphan')

class VendaItem(db.Model):
    __tablename__ = 'venda_itens'
    item_id = db.Column(db.Integer, primary_key=True)
    venda_id = db.Column(db.Integer, db.ForeignKey('vendas.venda_id'), nullable=False)
    livro_id = db.Column(db.Integer, db.ForeignKey('livros.livro_id'), nullable=False)
    quantidade = db.Column(db.Integer, nullable=False, default=1)
    preco_unitario = db.Column(db.Numeric(10, 2), nullable=False)
    venda = db.relationship('Venda', back_populates='itens')
    livro = db.relationship('Livro', back_populates='vendas_itens')

livro_autor = db.Table('livro_autor',
    db.Column('livro_id', db.Integer, db.ForeignKey('livros.livro_id'), primary_key=True),
    db.Column('autor_id', db.Integer, db.ForeignKey('autores.autor_id'), primary_key=True)
)