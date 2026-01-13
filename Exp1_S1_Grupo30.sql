-- caso 1 

DECLARE

    -- variables
    v_monto_total       NUMBER;
    v_tipo_cliente      VARCHAR2(100);
    v_pesos_total       NUMBER := 0;
    v_nombre_cliente    VARCHAR2(100);
    v_nro_cliente       NUMBER := 0;
    
    -- variables bind 
    v_run_cliente       VARCHAR2(20) := :b_run_ingresado; 
    v_peso_normal       NUMBER := :b_peso_normal;
    v_peso_extra_1      NUMBER := :b_peso_extra_1;
    v_peso_extra_2      NUMBER := :b_peso_extra_2;
    v_peso_extra_3      NUMBER := :b_peso_extra_3;
    v_tramo_1           NUMBER := :b_tramo_bajo;
    v_tramo_2           NUMBER := :b_tramo_alto;
BEGIN
    SELECT SUM(cc.monto_solicitado), tc.nombre_tipo_cliente, c.pnombre || ' ' || c.snombre || ' ' || c.appaterno || ' ' || c.apmaterno, c.nro_cliente
    INTO v_monto_total, v_tipo_cliente, v_nombre_cliente, v_nro_cliente
    FROM cliente c 
    JOIN credito_cliente cc ON c.nro_cliente = cc.nro_cliente
    JOIN tipo_cliente tc ON c.cod_tipo_cliente = tc.cod_tipo_cliente
    WHERE c.numrun || c.dvrun = v_run_cliente
      AND EXTRACT(YEAR FROM cc.fecha_solic_cred) = EXTRACT(YEAR FROM SYSDATE) - 1
      
    GROUP BY tc.nombre_tipo_cliente, c.pnombre, c.snombre, c.appaterno, c.apmaterno, c.snombre, c.nro_cliente;

    -- calculo de los pesos normales
    v_pesos_total := (TRUNC(v_monto_total / 100000) * v_peso_normal);

    -- verificar tramos correspondientes
    IF UPPER(v_tipo_cliente) LIKE '%INDEPENDIENTE%' THEN
        IF v_monto_total < v_tramo_1 THEN
             v_pesos_total := v_pesos_total + TRUNC(v_monto_total / 100000) * v_peso_extra_1;
             
        ELSIF v_monto_total BETWEEN v_tramo_1 AND v_tramo_2 THEN
             v_pesos_total := v_pesos_total + TRUNC(v_monto_total / 100000) * v_peso_extra_2;
             
        ELSIF v_monto_total > v_tramo_2 THEN
             v_pesos_total := v_pesos_total + TRUNC(v_monto_total / 100000) * v_peso_extra_3;
        END IF;
    END IF;
    INSERT INTO CLIENTE_TODOSUMA VALUES (v_nro_cliente, v_run_cliente, v_nombre_cliente, v_tipo_cliente, v_monto_total, v_pesos_total);
END;

-- caso 2

DECLARE

    -- variables
    v_ult_nro_cuota     NUMBER;
    v_ult_fecha_venc    DATE;
    v_valor_cuota_base  NUMBER;
    v_tipo_credito      VARCHAR2(100);
    v_tasa_interes      NUMBER := 0;
    v_creditos_ano_ant  NUMBER;
    v_nuevo_monto       NUMBER;

    -- variables bind
    v_nro_cliente       NUMBER := :b_nro_cliente;
    v_nro_solic         NUMBER := :b_nro_solic;
    v_cant_postergar    NUMBER := :b_cant_postergar;


BEGIN
    SELECT 
        MAX(cc.nro_cuota), 
        MAX(cc.fecha_venc_cuota),
        MAX(cc.valor_cuota), 
        cred.nombre_credito
    INTO 
        v_ult_nro_cuota, 
        v_ult_fecha_venc, 
        v_valor_cuota_base, 
        v_tipo_credito
    FROM cuota_credito_cliente cc
    JOIN credito_cliente soli ON cc.nro_solic_credito = soli.nro_solic_credito
    JOIN credito cred ON soli.cod_credito = cred.cod_credito
    WHERE cc.nro_solic_credito = v_nro_solic
    GROUP BY cred.nombre_credito;

    -- Tasas de interes
    IF UPPER(v_tipo_credito) LIKE '%CONSUMO%' THEN
        v_tasa_interes := 0.01;
    ELSIF UPPER(v_tipo_credito) LIKE '%AUTOMOTRIZ%' THEN
        v_tasa_interes := 0.02;
    ELSIF UPPER(v_tipo_credito) LIKE '%HIPOTECARIO%' THEN
        IF v_cant_postergar = 1 THEN
            v_tasa_interes := 0;
        ELSE
            v_tasa_interes := 0.005;
        END IF;
    END IF;

    -- Ciclo for para insertar nuevas cuotas    
    FOR i IN 1 .. v_cant_postergar LOOP
        v_nuevo_monto := v_valor_cuota_base + (v_valor_cuota_base * v_tasa_interes);
        
        INSERT INTO CUOTA_CREDITO_CLIENTE (
            nro_solic_credito, nro_cuota, fecha_venc_cuota, valor_cuota, 
            fecha_pago_cuota, monto_pagado, saldo_por_pagar, cod_forma_pago
        ) VALUES (
            v_nro_solic,
            v_ult_nro_cuota + i,
            ADD_MONTHS(v_ult_fecha_venc, i),
            ROUND(v_nuevo_monto),
            NULL, NULL, NULL, NULL
        );
    END LOOP;

    -- Condonacion contando los creditos del año pasado
    SELECT COUNT(*) INTO v_creditos_ano_ant
    FROM credito_cliente
    WHERE nro_cliente = v_nro_cliente
      AND EXTRACT(YEAR FROM fecha_solic_cred) = EXTRACT(YEAR FROM SYSDATE) - 1;

    IF v_creditos_ano_ant > 1 THEN
        -- update de la ultima cuota original
        UPDATE CUOTA_CREDITO_CLIENTE
        SET fecha_pago_cuota = fecha_venc_cuota,
            monto_pagado = valor_cuota,
            saldo_por_pagar = 0
        WHERE nro_solic_credito = v_nro_solic 
          AND nro_cuota = v_ult_nro_cuota;
    END IF;
END;