-- =====================================================================
-- 04 · CONSULTAS DE NEGÓCIO (nível base)
-- JOINs, subconsultas, agregações e filtros.
-- =====================================================================
USE manutencao_equipamentos;

-- ---------------------------------------------------------------------
-- Q1 · Que ordens de serviço foram concluídas e em quantos dias?
-- ---------------------------------------------------------------------
SELECT
    os.ID_OS,
    e.Nome AS Equipamento,
    os.Data_Abertura,
    os.Data_Fecho,
    DATEDIFF(os.Data_Fecho, os.Data_Abertura) AS Dias_Resolucao
FROM Ordens_Servico os
JOIN Equipamentos e ON os.ID_Equipamento = e.ID_Equipamento
WHERE os.Estado_OS = 'Concluída'
ORDER BY os.Data_Abertura, os.ID_OS;

-- ---------------------------------------------------------------------
-- Q2 · Que técnicos fizeram manutenção correctiva, e quantas?
-- ---------------------------------------------------------------------
SELECT
    t.Nome,
    t.Especialidade,
    COUNT(*) AS Num_Correctivas
FROM Tecnicos t
JOIN Intervencoes i ON t.ID_Tecnico = i.ID_Tecnico
WHERE i.Tipo_Manutencao = 'Correctiva'
GROUP BY t.ID_Tecnico, t.Nome, t.Especialidade
ORDER BY Num_Correctivas DESC, t.Nome;

-- ---------------------------------------------------------------------
-- Q3 · Que equipamentos nunca tiveram ordens de serviço?
-- NOT EXISTS é mais seguro do que NOT IN quando a subconsulta
-- pode devolver NULL.
-- ---------------------------------------------------------------------
SELECT
    e.Nome,
    e.Localizacao,
    e.Data_Aquisicao
FROM Equipamentos e
WHERE NOT EXISTS (
    SELECT 1
    FROM Ordens_Servico os
    WHERE os.ID_Equipamento = e.ID_Equipamento
);

-- ---------------------------------------------------------------------
-- Q4 · Qual é o custo total de cada ordem de serviço?
-- LEFT JOIN para incluir também OS sem custos (ex.: canceladas).
-- ---------------------------------------------------------------------
SELECT
    os.ID_OS,
    e.Nome                    AS Equipamento,
    os.Estado_OS,
    COALESCE(SUM(c.Valor), 0) AS Total_Custo
FROM Ordens_Servico os
JOIN Equipamentos e ON e.ID_Equipamento = os.ID_Equipamento
LEFT JOIN Custos c  ON c.ID_OS = os.ID_OS
GROUP BY os.ID_OS, e.Nome, os.Estado_OS
ORDER BY Total_Custo DESC, os.ID_OS;

-- ---------------------------------------------------------------------
-- Q5 · Que lançamentos de custo estão acima da média?
-- ---------------------------------------------------------------------
SELECT
    c.ID_OS,
    c.Tipo_Custo,
    c.Valor,
    ROUND((SELECT AVG(Valor) FROM Custos), 2) AS Media_Geral
FROM Custos c
WHERE c.Valor > (SELECT AVG(Valor) FROM Custos)
ORDER BY c.Valor DESC, c.ID_OS;

-- ---------------------------------------------------------------------
-- Q6 · Que peças foram usadas em cada intervenção, e em que equipamento?
-- ---------------------------------------------------------------------
SELECT
    i.ID_Intervencao,
    DATE(i.Data_Hora) AS Data,
    e.Nome            AS Equipamento,
    p.Nome            AS Peca,
    ip.Quantidade
FROM Intervencao_Peca ip
JOIN Pecas p          ON ip.ID_Peca = p.ID_Peca
JOIN Intervencoes i   ON ip.ID_Intervencao = i.ID_Intervencao
JOIN Ordens_Servico os ON os.ID_OS = i.ID_OS
JOIN Equipamentos e   ON e.ID_Equipamento = os.ID_Equipamento
ORDER BY i.Data_Hora, p.Nome;

-- ---------------------------------------------------------------------
-- Q7 · Que fornecedores vendem peças abaixo de 10 unidades monetárias?
-- ---------------------------------------------------------------------
SELECT
    f.Nome AS Fornecedor,
    p.Nome AS Peca,
    pf.Preco
FROM Fornecedores f
JOIN Peca_Fornecedor pf ON f.ID_Fornecedor = pf.ID_Fornecedor
JOIN Pecas p            ON p.ID_Peca = pf.ID_Peca
WHERE pf.Preco < 10
ORDER BY pf.Preco, f.Nome;

-- ---------------------------------------------------------------------
-- Q8 · Que técnicos têm mais de uma intervenção?
-- ---------------------------------------------------------------------
SELECT
    t.Nome,
    COUNT(*) AS Num_Intervencoes
FROM Tecnicos t
JOIN Intervencoes i ON i.ID_Tecnico = t.ID_Tecnico
GROUP BY t.ID_Tecnico, t.Nome
HAVING COUNT(*) > 1
ORDER BY Num_Intervencoes DESC, t.Nome;

-- ---------------------------------------------------------------------
-- Q9 · Que ordens de serviço estão pendentes, e há quantos dias?
-- (dias contados até ao fim do período dos dados: 31-12-2024)
-- ---------------------------------------------------------------------
SELECT
    os.ID_OS,
    e.Nome AS Equipamento,
    os.Prioridade,
    os.Estado_OS,
    os.Data_Abertura,
    DATEDIFF('2024-12-31', os.Data_Abertura) AS Dias_Em_Aberto
FROM Ordens_Servico os
JOIN Equipamentos e ON os.ID_Equipamento = e.ID_Equipamento
WHERE os.Estado_OS IN ('Aberta', 'Em Execução')
ORDER BY FIELD(os.Prioridade, 'Crítica', 'Alta', 'Média', 'Baixa'), os.Data_Abertura;

-- ---------------------------------------------------------------------
-- Q10 · Que equipamentos têm mais intervenções do que a média?
-- ---------------------------------------------------------------------
SELECT
    e.Nome,
    COUNT(i.ID_Intervencao) AS Total_Intervencoes
FROM Equipamentos e
JOIN Ordens_Servico os ON e.ID_Equipamento = os.ID_Equipamento
JOIN Intervencoes i    ON os.ID_OS = i.ID_OS
GROUP BY e.ID_Equipamento, e.Nome
HAVING COUNT(i.ID_Intervencao) > (
    SELECT AVG(Total)
    FROM (
        SELECT COUNT(i2.ID_Intervencao) AS Total
        FROM Ordens_Servico os2
        JOIN Intervencoes i2 ON os2.ID_OS = i2.ID_OS
        GROUP BY os2.ID_Equipamento
    ) sub
)
ORDER BY Total_Intervencoes DESC, e.Nome;
