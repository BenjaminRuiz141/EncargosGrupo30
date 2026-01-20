SET SERVEROUTPUT ON;

-- variable bind para la fecha
VARIABLE b_fecha_proceso VARCHAR2(10);
EXEC :b_fecha_proceso := TO_CHAR(SYSDATE, 'DD/MM/YYYY');

DECLARE

        -- variable para el nombre
        v_letra_estado_civil    VARCHAR2(1);
        v_letras_primer_nombre  VARCHAR2(3);
        v_largo_nombre          NUMBER;
        v_ult_digito_sueldo     NUMBER;
        v_dv_run                VARCHAR2(1);
        v_anios_trabajando      NUMBER;
        
        v_nombre_usuario        VARCHAR2(30);
        
        -- variables para la clave
        v_tercer_digito_run     VARCHAR2(1);
        v_anio_nacimiento       DATE;
        v_ult_digitos_sueldo    NUMBER;
        v_letras_ap_paterno     VARCHAR2(2);
        v_id_empleado           NUMBER;
        v_mes_anio_bdd          NUMBER;
        
        v_clave_usuario         VARCHAR2(50);

        -- variables
        v_id_min                empleado.id_emp%TYPE;
        v_id_max                empleado.id_emp%TYPE;
        v_id_actual             empleado.id_emp%TYPE;
        v_id_est_civil          empleado.id_estado_civil%TYPE;
        v_pnombre               VARCHAR2(30);
        v_snombre               VARCHAR2(30);
        v_appaterno             VARCHAR2(30);
        v_apmaterno             VARCHAR2(30);
        v_sueldo_base           NUMBER;   
        v_fecha_contrato        DATE;     
        v_fecha_nac             DATE;        
        v_desc_estado_civil     VARCHAR2(30);
        v_run_num               VARCHAR2(30);
        v_fecha_proc            DATE := TO_DATE(:b_fecha_proceso, 'DD/MM/YYYY');
        v_contador              NUMBER := 0;
        
        -- variables creacion
        v_a                     VARCHAR2(30);
        v_b                     VARCHAR2(30);
        v_c                     VARCHAR2(30);
        v_d                     VARCHAR2(30);
        v_e                     VARCHAR2(30);
        v_f                     VARCHAR2(30);
        v_g                     VARCHAR2(30);   
        v_h                     VARCHAR2(30);
        v_nombre_empleado       VARCHAR2(100);
        
BEGIN
    EXECUTE IMMEDIATE 'TRUNCATE TABLE USUARIO_CLAVE';
    
    -- obtenemos el id minimo y maximo para el rango 
    SELECT MIN(id_emp), MAX(id_emp)
    INTO v_id_min, v_id_max
    from empleado;
    DBMS_OUTPUT.PUT_LINE(v_id_min || ' ' || v_id_max);
    
    v_id_actual := v_id_min;
    
    SAVEPOINT sp_inicio;
    
    WHILE v_id_actual <= v_id_max LOOP
    
        v_contador := v_contador + 1;
    
        DBMS_OUTPUT.PUT_LINE('Procesando: ' || v_id_actual);
        
        -- creacion nombre de usuario, hacemos select para recuperar los datos mas importantes de el empleado
        SELECT numrun_emp, dvrun_emp, pnombre_emp, appaterno_emp, snombre_emp, apmaterno_emp, sueldo_base, id_estado_civil, fecha_contrato, fecha_nac
        INTO v_run_num, v_dv_run, v_pnombre, v_appaterno, v_snombre, v_apmaterno, v_sueldo_base, v_id_est_civil, v_fecha_contrato, v_anio_nacimiento
        FROM empleado
        WHERE id_emp = v_id_actual;
        
        SELECT nombre_estado_civil
        INTO v_desc_estado_civil
        FROM estado_civil
        WHERE id_estado_civil = v_id_est_civil;
        
        v_anios_trabajando := ROUND(MONTHS_BETWEEN(v_fecha_proc, v_fecha_contrato)/12);
        
        -- armamos con variables el nombre de usuario
        v_a := LOWER(SUBSTR(TO_CHAR(v_desc_estado_civil), 1, 1));
        v_b := SUBSTR(TO_CHAR(v_pnombre), 1, 3);
        v_c := TO_CHAR(LENGTH(v_pnombre));
        v_d := '*';
        v_e := SUBSTR(TO_CHAR(v_sueldo_base), -1);
        v_f := v_dv_run;
        v_g := v_anios_trabajando;
        
        IF v_anios_trabajando < 10 THEN
            v_nombre_usuario := v_a || v_b || v_c || v_d || v_e || v_f || v_g || 'X'; -- menos de 10 años
        ELSE v_nombre_usuario:= v_a || v_b || v_c || v_d || v_e || v_f || v_g;        -- mas de 10 años
        END IF;
        
        -- creacion de clave de usuario, tambien armamos la clave con variables
        v_a := SUBSTR(TO_CHAR(v_run_num), 3, 1);
        v_b := TO_CHAR(EXTRACT(YEAR FROM v_anio_nacimiento) + 2);
        v_c := TO_CHAR(TO_NUMBER(SUBSTR(TO_CHAR(v_sueldo_base - 1), -3)));
        IF v_id_est_civil = 10 OR v_id_est_civil = 60 THEN -- casado o acuerdo de union civil
            v_d := SUBSTR(v_appaterno, 1, 2); -- dos primeras letras
        ELSIF v_id_est_civil = 20 OR v_id_est_civil = 30 THEN -- divorciado o soltero
            v_d := SUBSTR(v_appaterno, 1, 1) || SUBSTR(v_appaterno, -1); -- primera y ultima
        ELSIF v_id_est_civil = 40 THEN -- viudo
            v_d := SUBSTR(v_appaterno, -3, 2); -- penultima y antepenúltima
        ELSE -- separado u otros
            v_d := SUBSTR(v_appaterno, -2); -- segunda y tercera letra
        END IF;
        v_d := LOWER(v_d);
        v_e := TO_CHAR(v_id_actual);
        v_f := TO_CHAR(v_fecha_proc, 'MMYYYY');
        
        v_clave_usuario := v_a || v_b || v_c || v_d || v_e || v_f;
        
        -- construccion del nombre completo
        v_nombre_empleado := v_pnombre || ' ' || v_snombre || ' ' || v_appaterno || ' ' || v_apmaterno;
        
        -- insertamos todos los datos necesarios a CLAVE_USUARIO
        INSERT INTO USUARIO_CLAVE (
            id_emp,
            numrun_emp,
            dvrun_emp,
            nombre_empleado,
            nombre_usuario,
            clave_usuario
        ) VALUES (
            v_id_actual,
            v_run_num,
            v_dv_run,
            v_nombre_empleado,
            v_nombre_usuario, 
            v_clave_usuario
        );
        -- 
        v_id_actual := v_id_actual + 10;
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('-- Procesados: ' || v_contador || ' Empleados --');
    COMMIT;
END;



        