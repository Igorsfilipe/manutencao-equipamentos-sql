-- =====================================================================
-- 01 · CRIAÇÃO DA BASE DE DADOS
-- Sistema de Gestão de Manutenção de Equipamentos de Telecomunicações
-- Requer MySQL 8.0.16 ou superior (testado em MySQL 8.0.46)
-- =====================================================================

DROP DATABASE IF EXISTS manutencao_equipamentos;
CREATE DATABASE manutencao_equipamentos
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_0900_ai_ci;
USE manutencao_equipamentos;

-- =====================================================================
-- EQUIPAMENTOS
-- Activos da rede sujeitos a manutenção.
-- =====================================================================
CREATE TABLE Equipamentos (
    ID_Equipamento     INT AUTO_INCREMENT PRIMARY KEY,
    Nome               VARCHAR(100) NOT NULL,
    Categoria          ENUM ('Rede Óptica', 'Rede IP', 'Segurança', 'Energia',
                             'Servidores', 'Infraestrutura', 'Climatização') NOT NULL,
    Modelo             VARCHAR(100),
    Numero_Serie       VARCHAR(100) NOT NULL,
    Localizacao        VARCHAR(100),
    Data_Aquisicao     DATE,
    Estado_Equipamento ENUM ('Operacional', 'Avariado', 'Em Manutenção', 'Inactivo')
                       NOT NULL DEFAULT 'Operacional',
    CONSTRAINT uq_equipamento_serie UNIQUE (Numero_Serie)
) ENGINE = InnoDB;

-- =====================================================================
-- ORDENS DE SERVIÇO (OS)
-- Pedido de trabalho aberto sobre um equipamento.
-- =====================================================================
CREATE TABLE Ordens_Servico (
    ID_OS              INT AUTO_INCREMENT PRIMARY KEY,
    ID_Equipamento     INT NOT NULL,
    Descricao_Problema VARCHAR(255) NOT NULL,
    Prioridade         ENUM ('Baixa', 'Média', 'Alta', 'Crítica') NOT NULL DEFAULT 'Média',
    Data_Abertura      DATE NOT NULL,
    Data_Fecho         DATE,
    Estado_OS          ENUM ('Aberta', 'Em Execução', 'Concluída', 'Cancelada') NOT NULL,
    CONSTRAINT fk_os_equipamento
        FOREIGN KEY (ID_Equipamento) REFERENCES Equipamentos (ID_Equipamento),
    -- Uma OS não pode fechar antes de abrir
    CONSTRAINT ck_os_datas
        CHECK (Data_Fecho IS NULL OR Data_Fecho >= Data_Abertura),
    -- Uma OS concluída tem obrigatoriamente data de fecho
    CONSTRAINT ck_os_concluida_com_fecho
        CHECK (Estado_OS <> 'Concluída' OR Data_Fecho IS NOT NULL)
) ENGINE = InnoDB;

-- =====================================================================
-- TÉCNICOS
-- =====================================================================
CREATE TABLE Tecnicos (
    ID_Tecnico    INT AUTO_INCREMENT PRIMARY KEY,
    Nome          VARCHAR(100) NOT NULL,
    Especialidade VARCHAR(100),
    Telefone      VARCHAR(30),
    Email         VARCHAR(100),
    CONSTRAINT uq_tecnico_email UNIQUE (Email)
) ENGINE = InnoDB;

-- =====================================================================
-- INTERVENÇÕES
-- Trabalho efectivo de um técnico dentro de uma OS (uma OS pode ter várias).
-- =====================================================================
CREATE TABLE Intervencoes (
    ID_Intervencao  INT AUTO_INCREMENT PRIMARY KEY,
    ID_OS           INT NOT NULL,
    ID_Tecnico      INT NOT NULL,
    Descricao       TEXT NOT NULL,
    Data_Hora       DATETIME NOT NULL,
    Duracao_Horas   DECIMAL(5,2) NOT NULL,
    Resultado       VARCHAR(50),
    Tipo_Manutencao ENUM ('Preventiva', 'Correctiva', 'Instalação', 'Atualização') NOT NULL,
    Observacoes     TEXT,
    CONSTRAINT fk_intervencao_os
        FOREIGN KEY (ID_OS) REFERENCES Ordens_Servico (ID_OS),
    CONSTRAINT fk_intervencao_tecnico
        FOREIGN KEY (ID_Tecnico) REFERENCES Tecnicos (ID_Tecnico),
    CONSTRAINT ck_intervencao_duracao
        CHECK (Duracao_Horas > 0)
) ENGINE = InnoDB;

-- =====================================================================
-- PEÇAS
-- =====================================================================
CREATE TABLE Pecas (
    ID_Peca            INT AUTO_INCREMENT PRIMARY KEY,
    Nome               VARCHAR(100) NOT NULL,
    Descricao          TEXT,
    Quantidade_Estoque INT NOT NULL DEFAULT 0,
    Stock_Minimo       INT NOT NULL DEFAULT 5,
    CONSTRAINT ck_peca_stock
        CHECK (Quantidade_Estoque >= 0 AND Stock_Minimo >= 0)
) ENGINE = InnoDB;

-- =====================================================================
-- FORNECEDORES
-- =====================================================================
CREATE TABLE Fornecedores (
    ID_Fornecedor INT AUTO_INCREMENT PRIMARY KEY,
    Nome          VARCHAR(100) NOT NULL,
    Contato       VARCHAR(100),
    Telefone      VARCHAR(30),
    Email         VARCHAR(100),
    CONSTRAINT uq_fornecedor_email UNIQUE (Email)
) ENGINE = InnoDB;

-- =====================================================================
-- N:N · PEÇAS x FORNECEDORES (preço praticado por cada fornecedor)
-- =====================================================================
CREATE TABLE Peca_Fornecedor (
    ID_Peca       INT NOT NULL,
    ID_Fornecedor INT NOT NULL,
    Preco         DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (ID_Peca, ID_Fornecedor),
    CONSTRAINT fk_pf_peca
        FOREIGN KEY (ID_Peca) REFERENCES Pecas (ID_Peca),
    CONSTRAINT fk_pf_fornecedor
        FOREIGN KEY (ID_Fornecedor) REFERENCES Fornecedores (ID_Fornecedor),
    CONSTRAINT ck_pf_preco
        CHECK (Preco > 0)
) ENGINE = InnoDB;

-- =====================================================================
-- N:N · INTERVENÇÕES x PEÇAS (quantidade consumida)
-- =====================================================================
CREATE TABLE Intervencao_Peca (
    ID_Intervencao INT NOT NULL,
    ID_Peca        INT NOT NULL,
    Quantidade     INT NOT NULL DEFAULT 1,
    PRIMARY KEY (ID_Intervencao, ID_Peca),
    CONSTRAINT fk_ip_intervencao
        FOREIGN KEY (ID_Intervencao) REFERENCES Intervencoes (ID_Intervencao)
        ON DELETE CASCADE,
    CONSTRAINT fk_ip_peca
        FOREIGN KEY (ID_Peca) REFERENCES Pecas (ID_Peca),
    CONSTRAINT ck_ip_quantidade
        CHECK (Quantidade > 0)
) ENGINE = InnoDB;

-- =====================================================================
-- CUSTOS
-- =====================================================================
CREATE TABLE Custos (
    ID_Custo   INT AUTO_INCREMENT PRIMARY KEY,
    ID_OS      INT NOT NULL,
    Valor      DECIMAL(10,2) NOT NULL,
    Data       DATE NOT NULL,
    Tipo_Custo ENUM ('Mão de Obra', 'Material', 'Deslocação',
                     'Serviços Externos', 'Outros') NOT NULL,
    CONSTRAINT fk_custo_os
        FOREIGN KEY (ID_OS) REFERENCES Ordens_Servico (ID_OS),
    CONSTRAINT ck_custo_valor
        CHECK (Valor > 0)
) ENGINE = InnoDB;

-- =====================================================================
-- ÍNDICES
-- O InnoDB já indexa automaticamente as chaves estrangeiras.
-- Estes índices servem os filtros e ordenações mais usados nos relatórios.
-- =====================================================================
CREATE INDEX idx_os_estado        ON Ordens_Servico (Estado_OS);
CREATE INDEX idx_os_data_abertura ON Ordens_Servico (Data_Abertura);
CREATE INDEX idx_int_tipo         ON Intervencoes (Tipo_Manutencao);
CREATE INDEX idx_custos_data_tipo ON Custos (Data, Tipo_Custo);
