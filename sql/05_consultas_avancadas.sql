-- =====================================================================
-- 05 · CONSULTAS ANALÍTICAS (nível avançado)
-- CTEs (WITH), funções de janela (OVER), indicadores de manutenção.
-- Requer MySQL 8.0 ou superior.
-- =====================================================================
USE manutencao_equipamentos;

-- ---------------------------------------------------------------------
-- A1 · Indicadores gerais (KPIs) de 2024
-- ---------------------------------------------------------------------
SELECT
    COUNT(*)                                                      AS Total_OS,
    SUM(Estado_OS = 'Concluída')                                  AS OS_Concluidas,
    SUM(Estado_OS IN ('Aberta', 'Em Execução'))                   AS OS_Pendentes,
    ROUND(100 * SUM(Estado_OS = 'Concluída') / COUNT(*), 1)       AS Taxa_Conclusao_Pct,
    ROUND(AVG(Dias_Resolucao), 2)                                 AS Tempo_Medio_Resolucao_Dias,
    SUM(Custo_Total)                                              AS Custo_Total,
    ROUND(SUM(Custo_Total) / SUM(Estado_OS = 'Concluída'), 2)     AS Custo_Medio_Por_OS_Concluida
FROM vw_os_detalhe;

-- ---------------------------------------------------------------------
-- A2 · Ranking de técnicos por horas trabalhadas
-- RANK() dá a posição; a quota mostra o peso de cada técnico na equipa.
-- ---------------------------------------------------------------------
SELECT
    Nome,
    Especialidade,
    Num_Intervencoes,
    Horas_Totais,
    RANK() OVER (ORDER BY Horas_Totais DESC)                      AS Posicao,
    ROUND(100 * Horas_Totais / SUM(Horas_Totais) OVER (), 1)      AS Quota_Horas_Pct
FROM vw_produtividade_tecnicos
ORDER BY Posicao, Nome;

-- ---------------------------------------------------------------------
-- A3 · Custo mensal, acumulado no ano e variação face ao mês anterior
-- ---------------------------------------------------------------------
WITH custo_mensal AS (
    SELECT
        DATE_FORMAT(Data, '%Y-%m') AS Mes,
        SUM(Valor)                 AS Custo
    FROM Custos
    GROUP BY DATE_FORMAT(Data, '%Y-%m')
)
SELECT
    Mes,
    Custo,
    SUM(Custo) OVER (ORDER BY Mes)                                AS Custo_Acumulado,
    Custo - LAG(Custo) OVER (ORDER BY Mes)                        AS Variacao,
    ROUND(100 * (Custo - LAG(Custo) OVER (ORDER BY Mes))
              / LAG(Custo) OVER (ORDER BY Mes), 1)                AS Variacao_Pct
FROM custo_mensal
ORDER BY Mes;

-- ---------------------------------------------------------------------
-- A4 · MTTR (tempo médio de reparação) por categoria de equipamento,
-- só para OS correctivas concluídas.
-- ---------------------------------------------------------------------
SELECT
    Categoria,
    COUNT(*)                         AS OS_Correctivas,
    ROUND(AVG(Dias_Resolucao), 2)    AS MTTR_Dias,
    ROUND(AVG(Horas_Trabalho), 2)    AS Horas_Medias_Por_OS,
    ROUND(AVG(Custo_Total), 2)       AS Custo_Medio
FROM vw_os_detalhe
WHERE Estado_OS = 'Concluída'
  AND Tipo_Manutencao = 'Correctiva'
GROUP BY Categoria
ORDER BY MTTR_Dias DESC, Categoria;

-- ---------------------------------------------------------------------
-- A5 · MTBF: intervalo médio entre avarias de cada equipamento.
-- LAG() vai buscar a data da avaria anterior do mesmo equipamento.
-- ---------------------------------------------------------------------
WITH avarias AS (
    SELECT
        ID_Equipamento,
        Equipamento,
        Data_Abertura,
        LAG(Data_Abertura) OVER (PARTITION BY ID_Equipamento
                                 ORDER BY Data_Abertura) AS Avaria_Anterior
    FROM vw_os_detalhe
    WHERE Tipo_Manutencao = 'Correctiva'
)
SELECT
    Equipamento,
    COUNT(*)                                                   AS Num_Avarias,
    ROUND(AVG(DATEDIFF(Data_Abertura, Avaria_Anterior)), 1)    AS MTBF_Dias,
    MIN(DATEDIFF(Data_Abertura, Avaria_Anterior))              AS Menor_Intervalo_Dias
FROM avarias
GROUP BY ID_Equipamento, Equipamento
HAVING COUNT(*) >= 2
ORDER BY MTBF_Dias, Equipamento;

-- ---------------------------------------------------------------------
-- A6 · Avarias repetidas: equipamento que voltou a avariar
-- em menos de 30 dias após a avaria anterior.
-- ---------------------------------------------------------------------
WITH avarias AS (
    SELECT
        ID_OS,
        Equipamento,
        Descricao_Problema,
        Data_Abertura,
        LAG(Data_Abertura) OVER (PARTITION BY ID_Equipamento
                                 ORDER BY Data_Abertura) AS Avaria_Anterior
    FROM vw_os_detalhe
    WHERE Tipo_Manutencao = 'Correctiva'
)
SELECT
    ID_OS,
    Equipamento,
    Descricao_Problema,
    Avaria_Anterior,
    Data_Abertura,
    DATEDIFF(Data_Abertura, Avaria_Anterior) AS Dias_Desde_Anterior
FROM avarias
WHERE DATEDIFF(Data_Abertura, Avaria_Anterior) < 30
ORDER BY Dias_Desde_Anterior, ID_OS;

-- ---------------------------------------------------------------------
-- A7 · Análise de Pareto: que equipamentos concentram 80% do custo?
-- ---------------------------------------------------------------------
WITH ranking AS (
    SELECT
        Equipamento,
        Custo_Total,
        SUM(Custo_Total) OVER (ORDER BY Custo_Total DESC, Equipamento) AS Acumulado,
        SUM(Custo_Total) OVER ()                                        AS Total_Geral
    FROM vw_custos_por_equipamento
    WHERE Custo_Total > 0
)
SELECT
    Equipamento,
    Custo_Total,
    ROUND(100 * Custo_Total / Total_Geral, 1) AS Peso_Pct,
    ROUND(100 * Acumulado   / Total_Geral, 1) AS Acumulado_Pct,
    CASE WHEN Acumulado - Custo_Total < 0.8 * Total_Geral
         THEN 'A · prioritário' ELSE 'B' END  AS Classe
FROM ranking
ORDER BY Custo_Total DESC, Equipamento;

-- ---------------------------------------------------------------------
-- A8 · Distribuição dos custos por tipo, com peso no total
-- ---------------------------------------------------------------------
SELECT
    Tipo_Custo,
    COUNT(*)                                          AS Lancamentos,
    SUM(Valor)                                        AS Total,
    ROUND(100 * SUM(Valor) / SUM(SUM(Valor)) OVER (), 1) AS Peso_Pct
FROM Custos
GROUP BY Tipo_Custo
ORDER BY Total DESC;

-- ---------------------------------------------------------------------
-- A9 · Fornecedor mais barato por peça e poupança face ao mais caro
-- ROW_NUMBER() escolhe uma única linha por peça.
-- ---------------------------------------------------------------------
WITH precos AS (
    SELECT
        p.Nome  AS Peca,
        f.Nome  AS Fornecedor,
        pf.Preco,
        ROW_NUMBER() OVER (PARTITION BY pf.ID_Peca ORDER BY pf.Preco) AS Ordem,
        COUNT(*)     OVER (PARTITION BY pf.ID_Peca)                   AS Num_Fornecedores,
        MAX(pf.Preco) OVER (PARTITION BY pf.ID_Peca)                  AS Preco_Maximo
    FROM Peca_Fornecedor pf
    JOIN Pecas p        ON p.ID_Peca = pf.ID_Peca
    JOIN Fornecedores f ON f.ID_Fornecedor = pf.ID_Fornecedor
)
SELECT
    Peca,
    Fornecedor                                     AS Melhor_Fornecedor,
    Preco                                          AS Melhor_Preco,
    Num_Fornecedores,
    Preco_Maximo,
    ROUND(100 * (Preco_Maximo - Preco) / Preco_Maximo, 1) AS Poupanca_Pct
FROM precos
WHERE Ordem = 1
ORDER BY Poupanca_Pct DESC, Peca;

-- ---------------------------------------------------------------------
-- A10 · Consumo de peças em 2024, valor e cobertura do stock actual
-- (quantos meses o stock dura ao ritmo de consumo deste ano)
-- ---------------------------------------------------------------------
WITH consumo AS (
    SELECT ID_Peca, SUM(Quantidade) AS Qtd_Consumida
    FROM Intervencao_Peca
    GROUP BY ID_Peca
)
SELECT
    p.Nome                                                    AS Peca,
    COALESCE(c.Qtd_Consumida, 0)                              AS Qtd_Consumida,
    ROUND(COALESCE(c.Qtd_Consumida, 0)
          * fn_preco_minimo_peca(p.ID_Peca), 2)               AS Valor_Consumido,
    p.Quantidade_Estoque,
    CASE WHEN c.Qtd_Consumida IS NULL THEN NULL
         ELSE ROUND(p.Quantidade_Estoque / (c.Qtd_Consumida / 12), 1)
    END                                                       AS Cobertura_Meses
FROM Pecas p
LEFT JOIN consumo c ON c.ID_Peca = p.ID_Peca
ORDER BY Valor_Consumido DESC, Peca;

-- ---------------------------------------------------------------------
-- A11 · Mix de manutenção por trimestre (preventiva vs correctiva)
-- Uma boa gestão aumenta a parte preventiva ao longo do tempo.
-- ---------------------------------------------------------------------
SELECT
    CONCAT(YEAR(Data_Hora), '-T', QUARTER(Data_Hora))              AS Trimestre,
    SUM(Tipo_Manutencao = 'Preventiva')                            AS Preventivas,
    SUM(Tipo_Manutencao = 'Correctiva')                            AS Correctivas,
    SUM(Tipo_Manutencao IN ('Instalação', 'Atualização'))          AS Outras,
    ROUND(100 * SUM(Tipo_Manutencao = 'Preventiva') / COUNT(*), 1) AS Preventiva_Pct
FROM Intervencoes
GROUP BY Trimestre
ORDER BY Trimestre;

-- ---------------------------------------------------------------------
-- A12 · Top 3 OS mais caras de cada categoria
-- DENSE_RANK() dentro de cada categoria (PARTITION BY).
-- ---------------------------------------------------------------------
WITH ordenado AS (
    SELECT
        Categoria,
        ID_OS,
        Equipamento,
        Descricao_Problema,
        Custo_Total,
        DENSE_RANK() OVER (PARTITION BY Categoria ORDER BY Custo_Total DESC) AS Pos
    FROM vw_os_detalhe
    WHERE Custo_Total > 0
)
SELECT Categoria, Pos, ID_OS, Equipamento, Descricao_Problema, Custo_Total
FROM ordenado
WHERE Pos <= 3
ORDER BY Categoria, Pos, ID_OS;
