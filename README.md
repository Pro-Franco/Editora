# Sistema de Gestão Editorial — Documentação Geral

# Tela de Login do Sistema WEB
<img width="996" height="707" alt="image" src="https://github.com/user-attachments/assets/bf79faf2-5c2c-43a0-b6fc-79088f176dde" />

# Dashboard do Sistema WEB
<img width="1253" height="743" alt="image" src="https://github.com/user-attachments/assets/788ef994-eedd-4bb4-b573-ab351f40f650" />


# Sistema de Gestão Editorial — Documentação Geral

Este documento descreve o funcionamento completo do banco de dados, procedimentos, funções, gatilhos e regras de negócio do **Sistema de Gestão Editorial**, permitindo que seja incluído diretamente no README do projeto.

## 📘 Visão Geral do Sistema

O objetivo deste sistema é gerenciar:

* Catálogo de livros
* Autores
* Clientes
* Vendas
* Itens de venda
* Controle de estoque
* Métricas avançadas para inteligência de negócio
* Segmentação de clientes
* Auditoria de preços

Além das tabelas principais, o sistema inclui **funções PL/pgSQL**, **triggers automatizados** e **views analíticas** para proporcionar um ambiente completo de gestão e análise.

---

# 🗂️ Estrutura do Banco de Dados

## Tabelas Principais

* `autores`: cadastro de autores
* `livros`: catálogo de livros
* `livro_autor`: relação muitos-para-muitos entre livros e autores
* `clientes`: cadastro de clientes
* `vendas`: vendas realizadas
* `vendas_item`: itens de cada venda
* `estoque`: controle de estoque por livro

## Tabelas de Inteligência de Negócios

* `metricas_autores`: vendas, receita e produtividade por autor
* `segmentacao_clientes`: classificação de clientes (VIP, Regular, etc.)
* `historico_precos`: auditoria de alterações de preço

---

# ⚙️ Funções do Sistema (Stored Procedures)

## 1. **sp_controle_estoque_alertas()**

Retorna:

* Estoques abaixo do mínimo
* Status do item (NORMAL, ALERTA, ESGOTADO)
* Vendas nos últimos 30 dias

## 2. **sp_analise_performance_autores(data_inicio, data_fim)**

Retorna análise completa por autor:

* Total de livros publicados
* Total de vendas
* Receita acumulada
* Média de vendas por livro

## 3. **sp_recomendacoes_cliente(cliente_id)**

Retorna recomendações de livros baseadas em:

* Autores já comprados
* Gêneros preferidos

## 4. **sp_analise_tendencias_genero(meses)**

Analisa:

* Vendas por gênero
* Crescimento percentual do período
* Ranking por receita

## 5. **sp_dashboard_vendas(data_início, data_fim)**

Fornece KPIs essenciais:

* Total vendido
* Ticket médio
* Clientes ativos
* Quantidade total de itens vendidos

---

# 🔄 Triggers do Sistema

## Validação de ISBN

Trigger: `tg_validar_isbn`

* Garante ISBN com 10 ou 13 dígitos

## Atualização automática de estoque

Trigger: `tg_atualizar_estoque_venda`

* Reduz quantidade após venda
* Emite alerta quando abaixo do mínimo

## Auditoria de alterações de preço

Trigger: `tg_log_alteracao_preco`

* Registra mudanças no valor unitário

## Atualização de métricas por autor

Trigger: `tg_atualizar_metricas_autor`

* Incrementa vendas e receita ao registrar itens

## Segmentação automática de clientes

Trigger: `tg_atualizar_segmentacao_cliente`

* Classifica cliente em: VIP, Regular, Novo, Inativo

---

# 📊 Conjunto de Dados de Demonstração

Inclui:

* 6 autores
* 8 livros
* 4 clientes
* Vendas para testes
* Estoque inicial
* Métricas pré-calculadas
* Segregação de clientes
* Histórico de preços

Permite testes completos das funções e consultas analíticas.

---

# ▶️ Consultas recomendadas para teste

```sql
SELECT * FROM sp_analise_performance_autores('2024-01-01', '2025-12-31');
SELECT * FROM sp_controle_estoque_alertas();
SELECT * FROM sp_recomendacoes_cliente(1);
SELECT * FROM sp_analise_tendencias_genero(6);
SELECT * FROM sp_dashboard_vendas();
```

---

# ✅ Benefícios do Sistema

* Totalmente modular
* Operações automatizadas
* Inteligência de negócio nativa
* Auditoria integrada
* Otimizado para relatórios e dashboards
* Facilmente expansível

---

# 📄 Uso recomendado do README

Você pode anexar este arquivo como:

* `/README.md`
* Documentação na wiki
* Arquivo de apresentação do projeto

Sinta-se livre para solicitar uma versão formatada em **Markdown avançado**, **PDF**, **README técnico**, **README para GitHub** ou **README para usuários finais**.
