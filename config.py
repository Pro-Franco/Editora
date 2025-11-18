import os
from datetime import timedelta

class Config:
    """Configuração padrão da aplicação"""
    SQLALCHEMY_DATABASE_URI = os.environ.get('DATABASE_URL') or \
        'postgresql://postgres:admin@localhost:5432/editora'
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    #SECRET_KEY = 'sua-chave-secreta-aqui'
    SECRET_KEY = os.environ.get('SECRET_KEY') or 'sua-chave-secreta-aqui'
    
    PERMANENT_SESSION_LIFETIME = timedelta(days=7)
    SESSION_COOKIE_HTTPONLY = True
    SESSION_PROTECTION = 'strong'
    WTF_CSRF_ENABLED = True  # Ativa CSRF globalmente
