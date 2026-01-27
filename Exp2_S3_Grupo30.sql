-- Caso 1

VAR b_fecha_proceso VARCHAR2(4);
EXEC :b_fecha_proceso := TO_CHAR(SYSDATE, 'YYYY');

DECLARE

    TYPE t_v_multas IS VARRAY(7) OF NUMBER;
    v_multas t_v_multas := t_v_multas(1200, 1300, 1700, 1900, 1100, 2000, 2300);
    
    v_annio_proceso NUMBER := :b_fecha_proceso;
    
    v_dias NUMBER;
    v_monto_multa NUMBER;
    v_monto_total NUMBER;
    
    v_edad NUMBER;
    v_porc_descto NUMBER;
    
    CURSOR c_atenciones IS
            SELECT 
                at.ate_id,
                at.esp_id,
                pa.pac_run, 
                pa.dv_run,
                pa.fecha_nacimiento,
                pa.pnombre || ' ' || pa.apaterno AS nombre_completo,
                pag.fecha_venc_pago,
                pag.fecha_pago,
                esp.nombre
            FROM atencion at
            JOIN paciente pa ON at.pac_run = pa.pac_run
            JOIN pago_atencion pag ON at.ate_id = pag.ate_id
            JOIN especialidad esp ON at.esp_id = esp.esp_id
            -- morosos del año anterior
            WHERE EXTRACT(YEAR FROM pag.fecha_venc_pago) = v_annio_proceso - 1
            AND pag.fecha_pago > pag.fecha_venc_pago
            ORDER BY pag.fecha_venc_pago ASC, pa.apaterno ASC;
            
    v_reg_atencion c_atenciones%ROWTYPE;
    
BEGIN
    EXECUTE IMMEDIATE 'TRUNCATE TABLE PAGO_MOROSO';
    
    OPEN c_atenciones;
    
    LOOP
        FETCH c_atenciones INTO v_reg_atencion;
        EXIT WHEN c_atenciones%NOTFOUND;
        
        CASE  
            WHEN v_reg_atencion.esp_id = 100 OR v_reg_atencion.esp_id = 300 THEN v_monto_multa := v_multas(1);
            WHEN v_reg_atencion.esp_id = 200 THEN v_monto_multa := v_multas(2);
            WHEN v_reg_atencion.esp_id = 400 OR v_reg_atencion.esp_id = 900 THEN v_monto_multa := v_multas(3);
            WHEN v_reg_atencion.esp_id = 500 OR v_reg_atencion.esp_id = 600 THEN v_monto_multa := v_multas(4);
            WHEN v_reg_atencion.esp_id = 700 THEN v_monto_multa := v_multas(5);
            WHEN v_reg_atencion.esp_id = 1100 THEN v_monto_multa := v_multas(6);
            WHEN v_reg_atencion.esp_id = 1400 OR v_reg_atencion.esp_id = 1800 THEN v_monto_multa := v_multas(7);
            ELSE v_monto_multa := 0;
        END CASE;
        
        v_dias := v_reg_atencion.fecha_pago - v_reg_atencion.fecha_venc_pago;
        
        v_monto_total := v_dias * v_monto_multa;
        
        v_edad := TRUNC(MONTHS_BETWEEN(SYSDATE, v_reg_atencion.fecha_nacimiento)/12);
        
        BEGIN
            SELECT porcentaje_descto INTO v_porc_descto
            FROM PORC_DESCTO_3RA_EDAD
            WHERE v_edad BETWEEN anno_ini AND anno_ter;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_porc_descto := 0;
        END;
        
        IF v_porc_descto > 0 THEN
                v_monto_total := v_monto_total - (v_monto_total * v_porc_descto / 100);
        END IF;
        
        INSERT INTO PAGO_MOROSO (
            PAC_RUN, 
            PAC_DV_RUN, 
            PAC_NOMBRE, 
            ATE_ID, 
            FECHA_VENC_PAGO, 
            FECHA_PAGO, 
            DIAS_MOROSIDAD, 
            ESPECIALIDAD_ATENCION, 
            MONTO_MULTA
        ) VALUES (
            v_reg_atencion.pac_run,
            v_reg_atencion.dv_run,
            v_reg_atencion.nombre_completo,
            v_reg_atencion.ate_id,
            v_reg_atencion.fecha_venc_pago,
            v_reg_atencion.fecha_pago,
            v_dias,
            v_reg_atencion.nombre,
            ROUND(v_monto_total)
        );
        
    END LOOP;
    CLOSE c_atenciones;

    
    
    NULL; 
END;

/




-- Caso 2

VAR b_fecha_proceso VARCHAR2(4);
EXEC :b_fecha_proceso := TO_CHAR(SYSDATE, 'YYYY');

DECLARE

    v_annio_proceso NUMBER := :b_fecha_proceso;
    
    TYPE t_v_destinos IS VARRAY(3) OF VARCHAR2(50);
    v_destinos t_v_destinos := t_v_destinos(
        'Servicio de Atención Primaria de Urgencia (SAPU)',
        'Hospitales del área de la Salud Pública',  
        'Centros de Salud Familiar (CESFAM)'     
    );
    
    CURSOR c_medicos IS
        SELECT 
            med.UNI_ID,
            UPPER(uni.NOMBRE) AS nombre_unidad_upper,
            uni.NOMBRE AS nombre_unidad_real,
            med.MED_RUN,
            med.DV_RUN,
            med.PNOMBRE || ' ' || med.SNOMBRE || ' ' || med.APATERNO || ' ' || med.AMATERNO AS nombre_completo,
            med.APATERNO, 
            (SELECT COUNT(*) 
             FROM ATENCION ate 
             WHERE ate.MED_RUN = med.MED_RUN 
               AND EXTRACT(YEAR FROM ate.FECHA_ATENCION) = v_annio_proceso - 1
            ) AS total_atenciones
        FROM MEDICO med
        JOIN UNIDAD uni ON med.UNI_ID = uni.UNI_ID
        ORDER BY uni.NOMBRE ASC, med.APATERNO ASC;

    v_reg_medico c_medicos%ROWTYPE;
    
    v_destinacion_final VARCHAR2(50);
    v_parte_apellido VARCHAR2(10);
    v_correo_generado VARCHAR2(50);
    
BEGIN
    EXECUTE IMMEDIATE 'TRUNCATE TABLE MEDICO_SERVICIO_COMUNIDAD';
    
    OPEN c_medicos;

    LOOP
        FETCH c_medicos INTO v_reg_medico;
        EXIT WHEN c_medicos%NOTFOUND;
        
        CASE 

            WHEN v_reg_medico.UNI_ID = 600 THEN
                v_destinacion_final := v_destinos(3);

            WHEN v_reg_medico.UNI_ID IN (300, 500, 900) THEN
                v_destinacion_final := v_destinos(2);

            WHEN v_reg_medico.UNI_ID IN (100, 400) THEN
                v_destinacion_final := v_destinos(1);
            
            WHEN v_reg_medico.UNI_ID IN (200, 700, 800, 1000) THEN
                
                IF v_reg_medico.total_atenciones <= 3 THEN
                    v_destinacion_final := v_destinos(1);
                ELSE
                    v_destinacion_final := v_destinos(2);
                END IF;
                
            ELSE
                v_destinacion_final := 'No hay asignacion';
        END CASE;

        v_parte_apellido := SUBSTR(v_reg_medico.APATERNO, -3, 2);
        
        v_correo_generado := SUBSTR(v_reg_medico.nombre_unidad_real, 1, 2) || 
                             v_parte_apellido || 
                             SUBSTR(TO_CHAR(v_reg_medico.MED_RUN), -3) || 
                             '@medicoktk.cl';

        INSERT INTO MEDICO_SERVICIO_COMUNIDAD (
                UNIDAD,
                RUN_MEDICO,
                NOMBRE_MEDICO,
                CORREO_INSTITUCIONAL,
                TOTAL_ATEN_MEDICAS,
                DESTINACION
            ) VALUES (
                v_reg_medico.nombre_unidad_real,
                TO_CHAR(v_reg_medico.MED_RUN) || '-' || v_reg_medico.DV_RUN,
                SUBSTR(v_reg_medico.nombre_completo, 1, 50),
                LOWER(v_correo_generado),
                v_reg_medico.total_atenciones,
                SUBSTR(v_destinacion_final, 1, 50)
            );

    END LOOP;

    CLOSE c_medicos;
    COMMIT;
    
END;
/





