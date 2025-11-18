--- Banco de dados versão final ---
--- Criação das tabelas

-- SCRIPT COMPLETO


CREATE TABLE autores (
    autor_id SERIAL PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    data_nascimento DATE,
    nacionalidade VARCHAR(50)
);

-- Tabela para armazenar informações dos livros
CREATE TABLE livros (
    livro_id SERIAL PRIMARY KEY,
    titulo VARCHAR(200) NOT NULL,
    isbn VARCHAR(13) UNIQUE NOT NULL,
    data_publicacao DATE,
    genero VARCHAR(50)
);

-- Tabela de relacionamento entre livros e autores (Muitos para Muitos)
CREATE TABLE livro_autor (
    livro_id INTEGER REFERENCES livros(livro_id),
    autor_id INTEGER REFERENCES autores(autor_id),
    PRIMARY KEY (livro_id, autor_id)
);

-- Tabela para armazenar os clientes da editora
CREATE TABLE clientes (
    cliente_id SERIAL PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    data_cadastro TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Tabela para registrar as vendas de livros
CREATE TABLE vendas (
    venda_id SERIAL PRIMARY KEY,
    cliente_id INTEGER REFERENCES clientes(cliente_id),
    data_venda DATE NOT NULL,
    valor_total NUMERIC(10, 2) NOT NULL CHECK (valor_total >= 0)
);

-- Tabela de detalhes de cada venda
CREATE TABLE vendas_item (
    venda_item_id SERIAL PRIMARY KEY,
    venda_id INTEGER REFERENCES vendas(venda_id),
    livro_id INTEGER REFERENCES livros(livro_id),
    quantidade INTEGER NOT NULL CHECK (quantidade > 0),
    preco_unitario NUMERIC(10, 2) NOT NULL CHECK (preco_unitario >= 0)
);


-- Tabela para controle de estoque (se não existir)
CREATE TABLE estoque (
    livro_id INTEGER PRIMARY KEY REFERENCES livros(livro_id),
    quantidade INTEGER NOT NULL DEFAULT 0 CHECK (quantidade >= 0),
    estoque_minimo INTEGER NOT NULL DEFAULT 10,
    data_atualizacao TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Tabela para métricas de autores
CREATE TABLE metricas_autores (
    autor_id INTEGER REFERENCES autores(autor_id),
    total_vendas INTEGER DEFAULT 0,
    receita_total NUMERIC(15,2) DEFAULT 0,
    livros_publicados INTEGER DEFAULT 0,
    data_atualizacao TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    PRIMARY KEY (autor_id)
);

-- Tabela para segmentação de clientes
CREATE TABLE segmentacao_clientes (
    cliente_id INTEGER REFERENCES clientes(cliente_id),
    segmento VARCHAR(20) CHECK (segmento IN ('VIP', 'Regular', 'Inativo', 'Novo')),
    total_compras INTEGER DEFAULT 0,
    valor_total_gasto NUMERIC(15,2) DEFAULT 0,
    ultima_compra DATE,
    data_atualizacao TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    PRIMARY KEY (cliente_id)
);

-- Tabela de histórico de preços
CREATE TABLE historico_precos (
    historico_id SERIAL PRIMARY KEY,
    livro_id INTEGER REFERENCES livros(livro_id),
    preco_antigo NUMERIC(10,2),
    preco_novo NUMERIC(10,2),
    data_alteracao TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    usuario VARCHAR(50)
);


---=== Inicio da criação das funções ===---

DROP FUNCTION IF EXISTS sp_controle_estoque_alertas();
CREATE OR REPLACE FUNCTION sp_controle_estoque_alertas()
RETURNS TABLE (
    livro_titulo VARCHAR(200),
    quantidade_estoque INTEGER,
    estoque_minimo INTEGER,
    status VARCHAR(20),
    vendas_ultimos_30_dias INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        l.titulo::VARCHAR(200) as livro_titulo,
        e.quantidade::INTEGER as quantidade_estoque,
        e.estoque_minimo::INTEGER as estoque_minimo,
        CASE 
            WHEN e.quantidade = 0 THEN 'ESGOTADO'::VARCHAR(20)
            WHEN e.quantidade <= e.estoque_minimo THEN 'ALERTA'::VARCHAR(20)
            ELSE 'NORMAL'::VARCHAR(20)
        END as status,
        COALESCE((
            SELECT SUM(vi.quantidade)::INTEGER
            FROM vendas_item vi
            JOIN vendas v ON vi.venda_id = v.venda_id
            WHERE vi.livro_id = l.livro_id
            AND v.data_venda >= CURRENT_DATE - INTERVAL '30 days'
        ), 0)::INTEGER as vendas_ultimos_30_dias
    FROM livros l
    JOIN estoque e ON l.livro_id = e.livro_id
    WHERE e.quantidade <= e.estoque_minimo
    ORDER BY e.quantidade ASC;
END;
$$ LANGUAGE plpgsql;


DROP FUNCTION IF EXISTS sp_analise_performance_autores(DATE, DATE);
CREATE OR REPLACE FUNCTION sp_analise_performance_autores(
    p_data_inicio DATE DEFAULT NULL,
    p_data_fim DATE DEFAULT NULL
)
RETURNS TABLE (
    autor_nome VARCHAR(100),
    nacionalidade VARCHAR(50),
    total_livros INTEGER,
    total_vendas INTEGER,
    receita_total NUMERIC(15,2),
    media_vendas_por_livro NUMERIC(10,2)
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        a.nome::VARCHAR(100) as autor_nome,
        a.nacionalidade::VARCHAR(50) as nacionalidade,
        COUNT(DISTINCT la.livro_id)::INTEGER as total_livros,
        COALESCE(SUM(vi.quantidade), 0)::INTEGER as total_vendas,
        COALESCE(SUM(vi.quantidade * vi.preco_unitario), 0)::NUMERIC(15,2) as receita_total,
        CASE 
            WHEN COUNT(DISTINCT la.livro_id) > 0 THEN 
                (COALESCE(SUM(vi.quantidade), 0)::NUMERIC / COUNT(DISTINCT la.livro_id)::NUMERIC)::NUMERIC(10,2)
            ELSE 0::NUMERIC(10,2)
        END as media_vendas_por_livro
    FROM autores a
    LEFT JOIN livro_autor la ON a.autor_id = la.autor_id
    LEFT JOIN livros l ON la.livro_id = l.livro_id
    LEFT JOIN vendas_item vi ON l.livro_id = vi.livro_id
    LEFT JOIN vendas v ON vi.venda_id = v.venda_id
    WHERE (p_data_inicio IS NULL OR v.data_venda >= p_data_inicio)
      AND (p_data_fim IS NULL OR v.data_venda <= p_data_fim)
    GROUP BY a.autor_id, a.nome, a.nacionalidade
    ORDER BY receita_total DESC;
END;
$$ LANGUAGE plpgsql;


DROP FUNCTION IF EXISTS sp_recomendacoes_cliente(INTEGER);
CREATE OR REPLACE FUNCTION sp_recomendacoes_cliente(
    p_cliente_id INTEGER
)
RETURNS TABLE (
    livro_titulo VARCHAR(200),
    autor_nome VARCHAR(100),
    genero VARCHAR(50),
    preco_medio NUMERIC(10,2),
    motivo_recomendacao VARCHAR(100)
) AS $$
BEGIN
    RETURN QUERY
    -- Baseado em autores que o cliente já comprou
    SELECT DISTINCT
        l.titulo::VARCHAR(200) as livro_titulo,
        a.nome::VARCHAR(100) as autor_nome,
        l.genero::VARCHAR(50) as genero,
        (SELECT AVG(preco_unitario)::NUMERIC(10,2) FROM vendas_item WHERE livro_id = l.livro_id) as preco_medio,
        'Mesmo autor'::VARCHAR(100) as motivo_recomendacao
    FROM livros l
    JOIN livro_autor la ON l.livro_id = la.livro_id
    JOIN autores a ON la.autor_id = a.autor_id
    WHERE la.autor_id IN (
        SELECT DISTINCT la2.autor_id
        FROM vendas_item vi
        JOIN vendas v ON vi.venda_id = v.venda_id
        JOIN livro_autor la2 ON vi.livro_id = la2.livro_id
        WHERE v.cliente_id = p_cliente_id
    )
    AND l.livro_id NOT IN (
        SELECT vi.livro_id
        FROM vendas_item vi
        JOIN vendas v ON vi.venda_id = v.venda_id
        WHERE v.cliente_id = p_cliente_id
    )
    
    UNION ALL
    
    -- Baseado em gêneros que o cliente gosta
    SELECT DISTINCT
        l.titulo::VARCHAR(200) as livro_titulo,
        a.nome::VARCHAR(100) as autor_nome,
        l.genero::VARCHAR(50) as genero,
        (SELECT AVG(preco_unitario)::NUMERIC(10,2) FROM vendas_item WHERE livro_id = l.livro_id) as preco_medio,
        'Mesmo gênero'::VARCHAR(100) as motivo_recomendacao
    FROM livros l
    JOIN livro_autor la ON l.livro_id = la.livro_id
    JOIN autores a ON la.autor_id = a.autor_id
    WHERE l.genero IN (
        SELECT DISTINCT l2.genero::VARCHAR(50)
        FROM vendas_item vi
        JOIN vendas v ON vi.venda_id = v.venda_id
        JOIN livros l2 ON vi.livro_id = l2.livro_id
        WHERE v.cliente_id = p_cliente_id
    )
    AND l.livro_id NOT IN (
        SELECT vi.livro_id
        FROM vendas_item vi
        JOIN vendas v ON vi.venda_id = v.venda_id
        WHERE v.cliente_id = p_cliente_id
    )
    
    ORDER BY preco_medio DESC
    LIMIT 10;
END;
$$ LANGUAGE plpgsql;


DROP FUNCTION IF EXISTS sp_analise_tendencias_genero(INTEGER);
CREATE OR REPLACE FUNCTION sp_analise_tendencias_genero(
    p_meses INTEGER DEFAULT 6
)
RETURNS TABLE (
    genero VARCHAR(50),
    total_vendas INTEGER,
    receita_total NUMERIC(15,2),
    crescimento_percentual NUMERIC(10,2),
    ranking INTEGER
) AS $$
BEGIN
    RETURN QUERY
    WITH vendas_periodo_atual AS (
        SELECT 
            l.genero::VARCHAR(50) as genero,
            SUM(vi.quantidade)::INTEGER as vendas_atual,
            SUM(vi.quantidade * vi.preco_unitario)::NUMERIC(15,2) as receita_atual
        FROM vendas_item vi
        JOIN vendas v ON vi.venda_id = v.venda_id
        JOIN livros l ON vi.livro_id = l.livro_id
        WHERE v.data_venda >= CURRENT_DATE - (p_meses || ' months')::INTERVAL
        GROUP BY l.genero
    ),
    vendas_periodo_anterior AS (
        SELECT 
            l.genero::VARCHAR(50) as genero,
            SUM(vi.quantidade)::INTEGER as vendas_anterior,
            SUM(vi.quantidade * vi.preco_unitario)::NUMERIC(15,2) as receita_anterior
        FROM vendas_item vi
        JOIN vendas v ON vi.venda_id = v.venda_id
        JOIN livros l ON vi.livro_id = l.livro_id
        WHERE v.data_venda >= CURRENT_DATE - (p_meses * 2 || ' months')::INTERVAL
          AND v.data_venda < CURRENT_DATE - (p_meses || ' months')::INTERVAL
        GROUP BY l.genero
    )
    SELECT 
        vpa.genero::VARCHAR(50) as genero,
        vpa.vendas_atual::INTEGER as total_vendas,
        vpa.receita_atual::NUMERIC(15,2) as receita_total,
        CASE 
            WHEN vpb.vendas_anterior > 0 THEN
                ((vpa.vendas_atual - vpb.vendas_anterior)::NUMERIC / vpb.vendas_anterior::NUMERIC * 100)::NUMERIC(10,2)
            ELSE 100::NUMERIC(10,2)
        END as crescimento_percentual,
        RANK() OVER (ORDER BY vpa.receita_atual DESC)::INTEGER as ranking
    FROM vendas_periodo_atual vpa
    LEFT JOIN vendas_periodo_anterior vpb ON vpa.genero = vpb.genero
    ORDER BY vpa.receita_atual DESC;
END;
$$ LANGUAGE plpgsql;


DROP FUNCTION IF EXISTS sp_dashboard_vendas(DATE, DATE);
CREATE OR REPLACE FUNCTION sp_dashboard_vendas(
    p_data_inicio DATE DEFAULT NULL,
    p_data_fim DATE DEFAULT NULL
)
RETURNS TABLE (
    metricas VARCHAR(100),
    valor NUMERIC(15,2),
    descricao TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        'Total Vendas'::VARCHAR(100) as metricas,
        COALESCE(SUM(v.valor_total), 0)::NUMERIC(15,2) as valor,
        'Soma total de todas as vendas'::TEXT as descricao
    FROM vendas v
    WHERE (p_data_inicio IS NULL OR v.data_venda >= p_data_inicio)
      AND (p_data_fim IS NULL OR v.data_venda <= p_data_fim)
    
    UNION ALL
    
    SELECT 
        'Ticket Médio'::VARCHAR(100),
        COALESCE(AVG(v.valor_total), 0)::NUMERIC(15,2),
        'Valor médio por venda'::TEXT
    FROM vendas v
    WHERE (p_data_inicio IS NULL OR v.data_venda >= p_data_inicio)
      AND (p_data_fim IS NULL OR v.data_venda <= p_data_fim)
    
    UNION ALL
    
    SELECT 
        'Total Clientes Ativos'::VARCHAR(100),
        COALESCE(COUNT(DISTINCT v.cliente_id), 0)::NUMERIC(15,2),
        'Clientes que realizaram compras'::TEXT
    FROM vendas v
    WHERE (p_data_inicio IS NULL OR v.data_venda >= p_data_inicio)
      AND (p_data_fim IS NULL OR v.data_venda <= p_data_fim)
    
    UNION ALL
    
    SELECT 
        'Livros Mais Vendidos'::VARCHAR(100),
        COALESCE(COUNT(vi.venda_item_id), 0)::NUMERIC(15,2),
        'Total de itens vendidos'::TEXT
    FROM vendas_item vi
    JOIN vendas v ON vi.venda_id = v.venda_id
    WHERE (p_data_inicio IS NULL OR v.data_venda >= p_data_inicio)
      AND (p_data_fim IS NULL OR v.data_venda <= p_data_fim);
END;
$$ LANGUAGE plpgsql;

-- Função do trigger tg_validar_isbn
CREATE OR REPLACE FUNCTION fn_validar_isbn()
RETURNS TRIGGER AS $$
BEGIN
    IF LENGTH(NEW.isbn) NOT IN (10, 13) THEN
        RAISE EXCEPTION 'ISBN deve ter 10 ou 13 caracteres';
    END IF;
    
    IF NOT (NEW.isbn ~ '^[0-9]{9}[0-9X]$' OR NEW.isbn ~ '^[0-9]{13}$') THEN
        RAISE EXCEPTION 'Formato de ISBN inválido';
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Função do trigger tg_atualizar_estoque_venda 
CREATE OR REPLACE FUNCTION fn_atualizar_estoque_venda()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE estoque 
    SET quantidade = quantidade - NEW.quantidade,
        data_atualizacao = NOW()
    WHERE livro_id = NEW.livro_id;
    
    IF (SELECT quantidade FROM estoque WHERE livro_id = NEW.livro_id) < 
       (SELECT estoque_minimo FROM estoque WHERE livro_id = NEW.livro_id) THEN
        RAISE NOTICE 'ALERTA: Estoque do livro ID % está abaixo do mínimo', NEW.livro_id;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Função do trigger tg_log_alteracao_preco 
CREATE OR REPLACE FUNCTION fn_log_alteracao_preco()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.preco_unitario IS DISTINCT FROM NEW.preco_unitario THEN
        INSERT INTO historico_precos (livro_id, preco_antigo, preco_novo, usuario)
        VALUES (NEW.livro_id, OLD.preco_unitario, NEW.preco_unitario, CURRENT_USER);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Função do trigger tg_atualizar_metricas_autor 
CREATE OR REPLACE FUNCTION fn_atualizar_metricas_autor()
RETURNS TRIGGER AS $$
DECLARE
    v_autor_id INTEGER;
BEGIN
    FOR v_autor_id IN 
        SELECT autor_id FROM livro_autor WHERE livro_id = NEW.livro_id
    LOOP
        INSERT INTO metricas_autores (autor_id, total_vendas, receita_total, livros_publicados)
        VALUES (
            v_autor_id, 
            NEW.quantidade, 
            NEW.quantidade * NEW.preco_unitario,
            1
        )
        ON CONFLICT (autor_id) 
        DO UPDATE SET
            total_vendas = metricas_autores.total_vendas + NEW.quantidade,
            receita_total = metricas_autores.receita_total + (NEW.quantidade * NEW.preco_unitario),
            data_atualizacao = NOW();
    END LOOP;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Função do trigger tg_atualizar_segmentacao_cliente 
CREATE OR REPLACE FUNCTION fn_atualizar_segmentacao_cliente()
RETURNS TRIGGER AS $$
DECLARE
    v_total_gasto NUMERIC(15,2);
    v_total_compras INTEGER;
    v_ultima_compra DATE;
    v_segmento VARCHAR(20);
BEGIN
    SELECT 
        COALESCE(SUM(valor_total), 0),
        COUNT(*),
        MAX(data_venda)
    INTO v_total_gasto, v_total_compras, v_ultima_compra
    FROM vendas 
    WHERE cliente_id = NEW.cliente_id;
    
    IF v_total_gasto > 1000 THEN
        v_segmento := 'VIP';
    ELSIF v_ultima_compra < CURRENT_DATE - INTERVAL '6 months' THEN
        v_segmento := 'Inativo';
    ELSIF v_total_compras = 1 THEN
        v_segmento := 'Novo';
    ELSE
        v_segmento := 'Regular';
    END IF;
    
    INSERT INTO segmentacao_clientes (cliente_id, segmento, total_compras, valor_total_gasto, ultima_compra)
    VALUES (NEW.cliente_id, v_segmento, v_total_compras, v_total_gasto, v_ultima_compra)
    ON CONFLICT (cliente_id) 
    DO UPDATE SET
        segmento = v_segmento,
        total_compras = v_total_compras,
        valor_total_gasto = v_total_gasto,
        ultima_compra = v_ultima_compra,
        data_atualizacao = NOW();
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- ======================================================================
-- 3. Inserção de Dados
-- ======================================================================


INSERT INTO autores (nome, data_nascimento, nacionalidade) VALUES
('Jane Austen', '1775-12-16', 'Inglesa'),
('George Orwell', '1903-06-25', 'Inglês'),
('Haruki Murakami', '1949-01-12', 'Japonês'),
('Gabriel Garcia Marquez', '1927-03-06', 'Colombiano'),
('Virginia Woolf', '1882-01-25', 'Inglesa'),
('Isaac Asimov', '1920-01-02', 'Russo-Americano');

INSERT INTO livros (titulo, isbn, data_publicacao, genero) VALUES
('Orgulho e Preconceito', '9788537807908', '1813-01-28', 'Romance'),
('1984', '9788535914849', '1949-06-08', 'Distopia'),
('Norwegian Wood', '9788544101889', '1987-09-01', 'Romance'),
('Cem Anos de Solidão', '9788501026046', '1967-05-30', 'Realismo Mágico'),
('Sra. Dalloway', '9788572328704', '1925-05-14', 'Ficção Moderna'),
('Fundação', '9788576570997', '1951-05-01', 'Ficção Científica'),
('A Metamorfose', '9788573215286', '1915-12-01', 'Ficção'),
('O Hobbit', '9788578270500', '1937-09-21', 'Fantasia');

INSERT INTO livro_autor (livro_id, autor_id) VALUES
(1, 1),
(2, 2),
(3, 3),
(4, 4),
(5, 5),
(6, 6);

INSERT INTO clientes (nome, email) VALUES
('Ana Clara', 'ana.clara@email.com'),
('Bruno Mendes', 'bruno.mendes@email.com'),
('Carla Silva', 'carla.silva@email.com'),
('Daniela Oliveira', 'daniela.oliveira@email.com');

INSERT INTO vendas (cliente_id, data_venda, valor_total) VALUES
(1, '2025-01-10', 35.90),
(2, '2025-01-15', 59.80),
(1, '2025-02-20', 71.90),
(3, '2025-03-05', 49.90),
(4, '2025-04-12', 35.90),
(2, '2025-05-01', 35.90);

INSERT INTO vendas_item (venda_id, livro_id, quantidade, preco_unitario) VALUES
(1, 1, 1, 35.90),
(2, 2, 1, 59.80),
(3, 3, 2, 35.95),
(4, 4, 1, 49.90),
(5, 1, 1, 35.90),
(6, 6, 1, 35.90);

-- INSERTS PARA TABELAS DE INTELIGÊNCIA DE NEGÓCIO

-- 1. Inserir dados de estoque
INSERT INTO estoque (livro_id, quantidade, estoque_minimo) VALUES
(1, 15, 5),
(2, 8, 3),
(3, 12, 4),
(4, 6, 3),
(5, 20, 6),
(6, 10, 4),
(7, 25, 8),
(8, 18, 6);

-- 2. Inserir métricas dos autores
INSERT INTO metricas_autores (autor_id, total_vendas, receita_total, livros_publicados) VALUES
(1, 2, 71.80, 1),
(2, 1, 59.80, 1),
(3, 2, 71.90, 1),
(4, 1, 49.90, 1),
(5, 0, 0.00, 1),
(6, 1, 35.90, 1);

-- 3. Inserir segmentação de clientes
INSERT INTO segmentacao_clientes (cliente_id, segmento, total_compras, valor_total_gasto, ultima_compra) VALUES
(1, 'VIP', 2, 107.80, '2025-02-20'),
(2, 'Regular', 2, 95.70, '2025-05-01'),
(3, 'Novo', 1, 49.90, '2025-03-05'),
(4, 'Novo', 1, 35.90, '2025-04-12');

-- 4. (Opcional) Histórico de preços para demonstração
INSERT INTO historico_precos (livro_id, preco_antigo, preco_novo, usuario) VALUES
(1, 32.90, 35.90, 'admin'),
(2, 55.00, 59.80, 'admin'),
(3, 33.50, 35.95, 'gerente'),
(6, 32.90, 35.90, 'sistema');

-- Verificar inserções

SELECT 'Estoque' as tabela, COUNT(*) as registros FROM estoque
UNION ALL
SELECT 'Métricas Autores', COUNT(*) FROM metricas_autores
UNION ALL
SELECT 'Segmentação Clientes', COUNT(*) FROM segmentacao_clientes
UNION ALL
SELECT 'Histórico Preços', COUNT(*) FROM historico_precos;


-- Testar todas as funções
SELECT * FROM sp_controle_estoque_alertas();
SELECT * FROM sp_analise_performance_autores();
SELECT * FROM sp_recomendacoes_cliente(1);
SELECT * FROM sp_analise_tendencias_genero(6);
SELECT * FROM sp_dashboard_vendas();



-- 1. Verificar performance dos autores
SELECT * FROM sp_analise_performance_autores('2024-01-01', '2025-12-31');

-- 2. Alertas de estoque
SELECT * FROM sp_controle_estoque_alertas();

-- 3. Recomendações para cliente específico
SELECT * FROM sp_recomendacoes_cliente(1);

-- 4. Tendências do mercado
SELECT * FROM sp_analise_tendencias_genero(6);

-- 5. Dashboard completo
SELECT * FROM sp_dashboard_vendas();



-- NÃO USAR CASO NÃO ESTEJA ATUALIZANDO O BANCO
-- RECOMENDADO: Fazer backup antes de limpar
-- Backup para tabela temporária
CREATE TABLE backup_autores AS SELECT * FROM autores;
CREATE TABLE backup_livros AS SELECT * FROM livros;
CREATE TABLE backup_livro_autor AS SELECT * FROM livro_autor;
CREATE TABLE backup_clientes AS SELECT * FROM clientes;
CREATE TABLE backup_vendas AS SELECT * FROM vendas;
CREATE TABLE backup_vendas_item AS SELECT * FROM vendas_item;
