SET SERVEROUTPUT ON;

VARIABLE b_periodo NUMBER
EXEC :b_periodo := EXTRACT(YEAR FROM SYSDATE) - 1;

DECLARE

    -- Tipos de transacción requeridos
    TYPE t_varray_tipo IS VARRAY(2) OF VARCHAR2(30);
    v_tipos_transaccion t_varray_tipo := t_varray_tipo('AVANCE EN EFECTIVO', 'SÚPER AVANCE EN EFECTIVO');

    -- Registro para el detalle de transacciones
    TYPE r_detalle IS RECORD (
      numrun              cliente.numrun%TYPE,
      dvrun               cliente.dvrun%TYPE,
      nro_tarjeta         tarjeta_cliente.nro_tarjeta%TYPE,
      nro_transaccion     transaccion_tarjeta_cliente.nro_transaccion%TYPE,
      fecha_transaccion   DATE,
      tipo_transaccion    VARCHAR2(30),
      monto_total         NUMBER
    );
    v_det r_detalle;

    -- Cursor de detalle
    CURSOR c_detalle IS 
        SELECT 
            c.numrun,
            c.dvrun,
            tc.nro_tarjeta,
            ttc.nro_transaccion,
            ttc.fecha_transaccion,
            tipo.nombre_tptran_tarjeta,
            ttc.monto_total_transaccion
        FROM cliente c
        JOIN tarjeta_cliente tc ON c.numrun = tc.numrun
        JOIN transaccion_tarjeta_cliente ttc ON tc.nro_tarjeta = ttc.nro_tarjeta
        JOIN tipo_transaccion_tarjeta tipo ON ttc.cod_tptran_tarjeta = tipo.cod_tptran_tarjeta
        WHERE EXTRACT(YEAR FROM ttc.fecha_transaccion) = :b_periodo
          AND UPPER(tipo.nombre_tptran_tarjeta) IN (
              v_tipos_transaccion(1),
              v_tipos_transaccion(2)
          )
        ORDER BY ttc.fecha_transaccion, c.numrun;

    -- Registro para el resumen mensual por tipo
    TYPE r_resumen IS RECORD (
        mes              NUMBER,
        tipo_transaccion VARCHAR2(30),
        monto_total      NUMBER
    );
    v_res r_resumen;

    -- Cursor con parámetro
    CURSOR c_resumen (p_mes NUMBER, p_tipo VARCHAR2) IS
        SELECT 
            EXTRACT(MONTH FROM ttc.fecha_transaccion),
            UPPER(tipo.nombre_tptran_tarjeta),
            SUM(ttc.monto_total_transaccion)
        FROM transaccion_tarjeta_cliente ttc
        JOIN tipo_transaccion_tarjeta tipo 
          ON ttc.cod_tptran_tarjeta = tipo.cod_tptran_tarjeta 
        WHERE EXTRACT(YEAR FROM ttc.fecha_transaccion) = :b_periodo
          AND EXTRACT(MONTH FROM ttc.fecha_transaccion) = p_mes
          AND UPPER(tipo.nombre_tptran_tarjeta) = UPPER(p_tipo)
        GROUP BY 
            EXTRACT(MONTH FROM ttc.fecha_transaccion),
            UPPER(tipo.nombre_tptran_tarjeta);

    -- Variables de calculo
    v_porcentaje  NUMBER;
    v_aporte      NUMBER;
    v_monto_total NUMBER;
    v_mes         NUMBER;


    -- Variable de control de datos
    v_total_reg   NUMBER := 0;


    -- Excepcion manual
    e_sin_datos   EXCEPTION;

BEGIN

    EXECUTE IMMEDIATE 'TRUNCATE TABLE DETALLE_APORTE_SBIF';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE RESUMEN_APORTE_SBIF';

    -- Validación de datos del período
    SELECT COUNT(*)
    INTO v_total_reg
    FROM transaccion_tarjeta_cliente ttc
    JOIN tipo_transaccion_tarjeta tipo 
      ON ttc.cod_tptran_tarjeta = tipo.cod_tptran_tarjeta
    WHERE EXTRACT(YEAR FROM fecha_transaccion) = :b_periodo
      AND UPPER(tipo.nombre_tptran_tarjeta) IN (
          v_tipos_transaccion(1),
          v_tipos_transaccion(2)
      );

    IF v_total_reg = 0 THEN
        RAISE e_sin_datos;
    END IF;

    -- Procesamiento de detalle
    OPEN c_detalle;
    LOOP
        FETCH c_detalle INTO v_det;
        EXIT WHEN c_detalle%NOTFOUND;

        v_monto_total := ROUND(v_det.monto_total);

        SELECT porc_aporte_sbif
        INTO   v_porcentaje
        FROM   tramo_aporte_sbif
        WHERE  v_monto_total BETWEEN tramo_inf_av_sav AND tramo_sup_av_sav;

        v_aporte := ROUND(v_monto_total * v_porcentaje / 100);

        INSERT INTO detalle_aporte_sbif VALUES (
            v_det.numrun,
            v_det.dvrun,
            v_det.nro_tarjeta,
            v_det.nro_transaccion,
            v_det.fecha_transaccion,
            v_det.tipo_transaccion,
            v_monto_total,
            v_aporte
        );
    END LOOP;
    CLOSE c_detalle;

    -- Procesamiento de resumen mensual
    FOR v_mes IN 1..12 LOOP
        FOR i IN 1..v_tipos_transaccion.COUNT LOOP
            OPEN c_resumen(v_mes, v_tipos_transaccion(i));
            LOOP
                FETCH c_resumen INTO v_res;
                EXIT WHEN c_resumen%NOTFOUND;

                v_monto_total := ROUND(v_res.monto_total);

                -- Obtener el porcentaje segun el tramo
                SELECT porc_aporte_sbif
                INTO   v_porcentaje
                FROM   tramo_aporte_sbif
                WHERE  v_monto_total BETWEEN tramo_inf_av_sav AND tramo_sup_av_sav;

                v_aporte := ROUND(v_monto_total * v_porcentaje / 100);

                INSERT INTO resumen_aporte_sbif VALUES (
                    LPAD(v_mes, 2, '0') || :b_periodo,
                    v_tipos_transaccion(i),
                    v_monto_total,
                    v_aporte
                );
            END LOOP;
            CLOSE c_resumen;
        END LOOP;
    END LOOP;
    
    COMMIT;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('Error: tramo SBIF no encontrado');
    WHEN e_sin_datos THEN
        DBMS_OUTPUT.PUT_LINE('No existen transacciones para el periodo');
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLCODE || ' - ' || SQLERRM);
END;
/