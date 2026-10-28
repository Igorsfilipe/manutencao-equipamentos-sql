-- =====================================================================
-- 06 · DEMONSTRAÇÃO DAS PROCEDURES E TRIGGERS
-- Tudo corre dentro de uma transacção que termina em ROLLBACK,
-- por isso os dados ficam exactamente como estavam.
-- =====================================================================
USE manutencao_equipamentos;

START TRANSACTION;

-- 1) Ficha de manutenção de um equipamento
CALL sp_historico_equipamento(1);

-- 2) Abrir uma OS crítica: o equipamento passa a 'Avariado'
CALL sp_abrir_os(3, 'Router sem sinal na porta PON 2', 'Crítica', @nova_os);
SELECT @nova_os AS Nova_OS;
SELECT Nome, Estado_Equipamento FROM Equipamentos WHERE ID_Equipamento = 3;

-- 3) Registar a intervenção e as peças usadas.
--    O trigger desconta automaticamente o stock.
SELECT Nome, Quantidade_Estoque AS Stock_Antes FROM Pecas WHERE ID_Peca = 1;

INSERT INTO Intervencoes (ID_OS, ID_Tecnico, Descricao, Data_Hora,
                          Duracao_Horas, Resultado, Tipo_Manutencao)
VALUES (@nova_os, 7, 'Substituição de conectores e medição OTDR', NOW(),
        2.5, 'Resolvido', 'Correctiva');

INSERT INTO Intervencao_Peca (ID_Intervencao, ID_Peca, Quantidade)
VALUES (LAST_INSERT_ID(), 1, 4);

SELECT Nome, Quantidade_Estoque AS Stock_Depois FROM Pecas WHERE ID_Peca = 1;

-- 4) Fechar a OS: fica 'Concluída' e o equipamento volta a 'Operacional'
CALL sp_fechar_os(@nova_os);
SELECT ID_OS, Estado_OS, Data_Fecho FROM Ordens_Servico WHERE ID_OS = @nova_os;
SELECT Nome, Estado_Equipamento FROM Equipamentos WHERE ID_Equipamento = 3;

-- 5) Função de custo
SELECT fn_custo_total_os(1) AS Custo_OS_1;

ROLLBACK;  -- desfaz tudo o que foi feito acima

-- =====================================================================
-- TESTES DE REGRAS DE NEGÓCIO
-- Cada comando abaixo DEVE FALHAR com uma mensagem clara.
-- Para testar: retirar o "--" de um comando e executá-lo sozinho (DBeaver: Ctrl+Enter).
-- =====================================================================

-- Stock insuficiente (trigger trg_ip_valida_stock) → Error Code: 1644
-- INSERT INTO Intervencao_Peca (ID_Intervencao, ID_Peca, Quantidade) VALUES (1, 9, 500);

-- Fechar uma OS sem intervenções (procedure sp_fechar_os) → Error Code: 1644
-- CALL sp_fechar_os(57);

-- Data de fecho anterior à abertura (CHECK ck_os_datas) → Error Code: 3819
-- UPDATE Ordens_Servico SET Data_Fecho = '2023-01-01' WHERE ID_OS = 1;

-- Número de série duplicado (UNIQUE uq_equipamento_serie) → Error Code: 1062
-- INSERT INTO Equipamentos (Nome, Categoria, Numero_Serie) VALUES ('Teste', 'Rede IP', 'SN001');
