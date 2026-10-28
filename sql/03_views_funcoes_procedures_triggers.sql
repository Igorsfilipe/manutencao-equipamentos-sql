-- =====================================================================
-- 03 · VIEWS, FUNÇÕES, PROCEDURES E TRIGGERS
-- Lógica de negócio guardada na própria base de dados.
-- Executar depois de 01 e 02.
-- =====================================================================
USE manutencao_equipamentos;

-- =====================================================================
-- VIEWS
-- =====================================================================

-- ---------------------------------------------------------------------
-- vw_os_detalhe · uma linha por OS com tudo o que um gestor quer ver.
-- É a tabela base ideal para ligar ao Power BI.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_os_detalhe AS
SELECT
    os.ID_OS,
    e.ID_Equipamento,
    e.Nome                                       AS Equipamento,
    e.Categoria,
    e.Localizacao,
    os.Descricao_Problema,
    os.Prioridade,
    os.Estado_OS,
    os.Data_Abertura,
    os.Data_Fecho,
    DATEDIFF(os.Data_Fecho, os.Data_Abertura)    AS Dias_Resolucao,
    COALESCE(i.Num_Intervencoes, 0)              AS Num_Intervencoes,
    COALESCE(i.Horas_Trabalho, 0)                AS Horas_Trabalho,
    i.Tipo_Principal                             AS Tipo_Manutencao,
    COALESCE(c.Custo_Total, 0)                   AS Custo_Total
FROM Ordens_Servico os
JOIN Equipamentos e ON e.ID_Equipamento = os.ID_Equipamento
LEFT JOIN (
    SELECT ID_OS,
           COUNT(*)             AS Num_Intervencoes,
           SUM(Duracao_Horas)   AS Horas_Trabalho,
           MAX(Tipo_Manutencao) AS Tipo_Principal  -- nos dados, cada OS tem um só tipo
    FROM Intervencoes
    GROUP BY ID_OS
) i ON i.ID_OS = os.ID_OS
LEFT JOIN (
    SELECT ID_OS, SUM(Valor) AS Custo_Total
    FROM Custos
    GROUP BY ID_OS
) c ON c.ID_OS = os.ID_OS;

-- ---------------------------------------------------------------------
-- vw_custos_por_equipamento · custo acumulado e nº de OS por equipamento
-- (inclui equipamentos sem OS, com zero).
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_custos_por_equipamento AS
SELECT
    e.ID_Equipamento,
    e.Nome AS Equipamento,
    e.Categoria,
    COUNT(DISTINCT os.ID_OS)                                             AS Num_OS,
    COALESCE(SUM(CASE WHEN c.Tipo_Custo = 'Mão de Obra' THEN c.Valor END), 0) AS Custo_Mao_Obra,
    COALESCE(SUM(CASE WHEN c.Tipo_Custo = 'Material'    THEN c.Valor END), 0) AS Custo_Material,
    COALESCE(SUM(CASE WHEN c.Tipo_Custo NOT IN ('Mão de Obra', 'Material')
                      THEN c.Valor END), 0)                                   AS Custo_Outros,
    COALESCE(SUM(c.Valor), 0)                                            AS Custo_Total
FROM Equipamentos e
LEFT JOIN Ordens_Servico os ON os.ID_Equipamento = e.ID_Equipamento
LEFT JOIN Custos c          ON c.ID_OS = os.ID_OS
GROUP BY e.ID_Equipamento, e.Nome, e.Categoria;

-- ---------------------------------------------------------------------
-- vw_stock_critico · peças no stock mínimo ou abaixo, com o fornecedor
-- mais barato para encomendar.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_stock_critico AS
SELECT
    p.ID_Peca,
    p.Nome                                AS Peca,
    p.Quantidade_Estoque,
    p.Stock_Minimo,
    p.Stock_Minimo - p.Quantidade_Estoque AS Em_Falta,
    f.Nome                                AS Fornecedor_Mais_Barato,
    pf.Preco                              AS Preco_Unitario
FROM Pecas p
JOIN Peca_Fornecedor pf ON pf.ID_Peca = p.ID_Peca
JOIN Fornecedores f     ON f.ID_Fornecedor = pf.ID_Fornecedor
WHERE p.Quantidade_Estoque <= p.Stock_Minimo
  AND pf.Preco = (SELECT MIN(pf2.Preco)
                  FROM Peca_Fornecedor pf2
                  WHERE pf2.ID_Peca = p.ID_Peca);

-- ---------------------------------------------------------------------
-- vw_produtividade_tecnicos · carga de trabalho por técnico
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_produtividade_tecnicos AS
SELECT
    t.ID_Tecnico,
    t.Nome,
    t.Especialidade,
    COUNT(i.ID_Intervencao)                                       AS Num_Intervencoes,
    COUNT(DISTINCT i.ID_OS)                                       AS Num_OS,
    COALESCE(SUM(i.Duracao_Horas), 0)                             AS Horas_Totais,
    SUM(CASE WHEN i.Tipo_Manutencao = 'Correctiva' THEN 1 ELSE 0 END) AS Num_Correctivas
FROM Tecnicos t
LEFT JOIN Intervencoes i ON i.ID_Tecnico = t.ID_Tecnico
GROUP BY t.ID_Tecnico, t.Nome, t.Especialidade;


-- =====================================================================
-- FUNÇÕES
-- =====================================================================
DROP FUNCTION IF EXISTS fn_custo_total_os;
DROP FUNCTION IF EXISTS fn_preco_minimo_peca;

DELIMITER $$

-- Custo total de uma OS (0 se não tiver custos)
CREATE FUNCTION fn_custo_total_os(p_id_os INT)
RETURNS DECIMAL(10,2)
READS SQL DATA
BEGIN
    DECLARE v_total DECIMAL(10,2);
    SELECT COALESCE(SUM(Valor), 0) INTO v_total
    FROM Custos
    WHERE ID_OS = p_id_os;
    RETURN v_total;
END$$

-- Melhor preço disponível para uma peça
CREATE FUNCTION fn_preco_minimo_peca(p_id_peca INT)
RETURNS DECIMAL(10,2)
READS SQL DATA
BEGIN
    DECLARE v_preco DECIMAL(10,2);
    SELECT MIN(Preco) INTO v_preco
    FROM Peca_Fornecedor
    WHERE ID_Peca = p_id_peca;
    RETURN v_preco;
END$$

DELIMITER ;


-- =====================================================================
-- TRIGGERS · controlo automático de stock
-- =====================================================================
DROP TRIGGER IF EXISTS trg_ip_valida_stock;
DROP TRIGGER IF EXISTS trg_ip_abate_stock;
DROP TRIGGER IF EXISTS trg_ip_repoe_stock;

DELIMITER $$

-- Impede consumir mais peças do que as existentes em stock
CREATE TRIGGER trg_ip_valida_stock
BEFORE INSERT ON Intervencao_Peca
FOR EACH ROW
BEGIN
    DECLARE v_stock INT;
    SELECT Quantidade_Estoque INTO v_stock
    FROM Pecas
    WHERE ID_Peca = NEW.ID_Peca;
    IF v_stock < NEW.Quantidade THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Stock insuficiente para a peça pedida.';
    END IF;
END$$

-- Desconta do stock as peças usadas numa intervenção
CREATE TRIGGER trg_ip_abate_stock
AFTER INSERT ON Intervencao_Peca
FOR EACH ROW
BEGIN
    UPDATE Pecas
    SET Quantidade_Estoque = Quantidade_Estoque - NEW.Quantidade
    WHERE ID_Peca = NEW.ID_Peca;
END$$

-- Se o registo for apagado (lançamento errado), devolve as peças ao stock
CREATE TRIGGER trg_ip_repoe_stock
AFTER DELETE ON Intervencao_Peca
FOR EACH ROW
BEGIN
    UPDATE Pecas
    SET Quantidade_Estoque = Quantidade_Estoque + OLD.Quantidade
    WHERE ID_Peca = OLD.ID_Peca;
END$$

DELIMITER ;


-- =====================================================================
-- STORED PROCEDURES
-- =====================================================================
DROP PROCEDURE IF EXISTS sp_abrir_os;
DROP PROCEDURE IF EXISTS sp_fechar_os;
DROP PROCEDURE IF EXISTS sp_historico_equipamento;

DELIMITER $$

-- ---------------------------------------------------------------------
-- sp_abrir_os · abre uma OS e, se for urgente, marca o equipamento
-- como avariado. Devolve o ID da nova OS.
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_abrir_os(
    IN  p_id_equipamento INT,
    IN  p_descricao      VARCHAR(255),
    IN  p_prioridade     VARCHAR(10),
    OUT p_id_os          INT
)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Equipamentos WHERE ID_Equipamento = p_id_equipamento) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Equipamento inexistente.';
    END IF;
    INSERT INTO Ordens_Servico (ID_Equipamento, Descricao_Problema, Prioridade,
                                Data_Abertura, Estado_OS)
    VALUES (p_id_equipamento, p_descricao, p_prioridade, CURDATE(), 'Aberta');
    SET p_id_os = LAST_INSERT_ID();
    IF p_prioridade IN ('Alta', 'Crítica') THEN
        UPDATE Equipamentos
        SET Estado_Equipamento = 'Avariado'
        WHERE ID_Equipamento = p_id_equipamento;
    END IF;
END$$

-- ---------------------------------------------------------------------
-- sp_fechar_os · conclui uma OS, com validações de negócio:
--   · a OS tem de existir e estar Aberta ou Em Execução;
--   · tem de ter pelo menos uma intervenção registada.
-- Se o equipamento não tiver outras OS pendentes, volta a Operacional.
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_fechar_os(IN p_id_os INT)
BEGIN
    DECLARE v_estado VARCHAR(20);
    DECLARE v_equip  INT;
    SELECT Estado_OS, ID_Equipamento INTO v_estado, v_equip
    FROM Ordens_Servico
    WHERE ID_OS = p_id_os;
    IF v_estado IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ordem de serviço inexistente.';
    END IF;
    IF v_estado IN ('Concluída', 'Cancelada') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A ordem de serviço já está encerrada.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM Intervencoes WHERE ID_OS = p_id_os) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Não é possível fechar uma OS sem intervenções registadas.';
    END IF;
    UPDATE Ordens_Servico
    SET Estado_OS  = 'Concluída',
        Data_Fecho = GREATEST(CURDATE(), Data_Abertura)
    WHERE ID_OS = p_id_os;
    IF NOT EXISTS (SELECT 1 FROM Ordens_Servico
                   WHERE ID_Equipamento = v_equip
                     AND Estado_OS IN ('Aberta', 'Em Execução')) THEN
        UPDATE Equipamentos
        SET Estado_Equipamento = 'Operacional'
        WHERE ID_Equipamento = v_equip;
    END IF;
END$$

-- ---------------------------------------------------------------------
-- sp_historico_equipamento · ficha de manutenção de um equipamento
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_historico_equipamento(IN p_id_equipamento INT)
BEGIN
    SELECT ID_OS, Data_Abertura, Data_Fecho, Prioridade, Estado_OS,
           Descricao_Problema, Num_Intervencoes, Horas_Trabalho, Custo_Total
    FROM vw_os_detalhe
    WHERE ID_Equipamento = p_id_equipamento
    ORDER BY Data_Abertura, ID_OS;
END$$

DELIMITER ;
