-- CASO 1 --


-- Trigger para consumos 
CREATE OR REPLACE TRIGGER trg_actualiza_consumos
AFTER
INSERT OR UPDATE OR DELETE ON consumo
FOR EACH ROW

DECLARE

v_count     NUMBER; -- Variable para contar 

BEGIN
    IF INSERTING THEN
        SELECT COUNT(*) INTO v_count -- En cada caso verificamos si existe en la tabla TOTAL_CONSUMOS
        FROM total_consumos
        WHERE id_huesped = :NEW.id_huesped;
        
        IF v_count = 0 THEN
        -- Si es nuevo, creamos el registro con el monto del primer consumo
            INSERT INTO total_consumos 
            VALUES (:NEW.id_huesped, :NEW.monto);
        ELSE
        -- Si ya existe, le sumamos el consumo nuevo al total
            UPDATE total_consumos 
            SET monto_consumos = monto_consumos + :NEW.monto
            WHERE id_huesped = :NEW.id_huesped;
        END IF;
    
    ELSIF UPDATING THEN
        SELECT COUNT(*) INTO v_count
        FROM total_consumos
        WHERE id_huesped = :OLD.id_huesped;
        
        IF v_count = 0 THEN
        -- Si no existe lanzamos un error
            RAISE_APPLICATION_ERROR(-20001, 'Huesped con id: '|| :OLD.id_huesped ||' no existe en TOTAL_CONSUMOS');
        ELSE
        -- Actualizamos con el monto anterior sumandole el nuevo
            UPDATE total_consumos 
            SET monto_consumos = monto_consumos - :OLD.monto + :NEW.monto
            WHERE id_huesped = :OLD.id_huesped;
        END IF;
    ELSIF DELETING THEN
        SELECT COUNT(*) INTO v_count
        FROM total_consumos
        WHERE id_huesped = :OLD.id_huesped;
        
        IF v_count = 0 THEN
            RAISE_APPLICATION_ERROR(-20001, 'Huesped con id: '|| :OLD.id_huesped ||' no existe en TOTAL_CONSUMOS');
        ELSE
        -- Restamos el monto a el monto total
            UPDATE total_consumos 
            SET monto_consumos = monto_consumos - :OLD.monto
            WHERE id_huesped = :OLD.id_huesped;
        END IF;
    END IF;

EXCEPTION
    -- Capturamos errores y los insertamos en la tabla reg_errores
    WHEN OTHERS THEN
        DECLARE
            v_error VARCHAR2(300) := SQLERRM;
        BEGIN
            INSERT INTO reg_errores (id_error, nomsubprograma, msg_error)
            VALUES (sq_error.NEXTVAL, 'trg_actualiza_consumos', v_error);
        END;
END;
/


-- Bloque de pruebas
DECLARE
    v_max_id NUMBER; 
BEGIN

    SELECT MAX(id_consumo) INTO v_max_id FROM consumo;
    
    INSERT INTO consumo (id_consumo, id_reserva, id_huesped, monto)
    VALUES (v_max_id + 1, 1587, 340006, 150);
    
    DELETE FROM consumo 
    WHERE id_consumo = 11473;
    
    UPDATE consumo 
    SET monto = 95
    WHERE id_consumo = 10688;
    
    COMMIT;

EXCEPTION
    WHEN OTHERS THEN
        DECLARE
            v_error VARCHAR2(300) := SQLERRM;
        BEGIN
            INSERT INTO reg_errores (id_error, nomsubprograma, msg_error)
            VALUES (sq_error.NEXTVAL, 'trg_actualiza_consumos', v_error);
        END;
END;
/

SELECT * FROM reg_errores;
SELECT * FROM TOTAL_CONSUMOS
WHERE id_huesped BETWEEN 340003 AND 340009;

SELECT * FROM CONSUMO
WHERE id_huesped BETWEEN 340003 AND 340009;

-- Verificar valores de el insert con monto 150
SELECT * FROM consumo WHERE monto = 150;

-- Verificar si fue eliminado 11473
SELECT * FROM consumo WHERE id_consumo = 11473;

-- Verificar si el id 10688 tiene como valor 95
SELECT * FROM consumo WHERE id_consumo = 10688;






-- CASO 2 --

-- Funcion que retorna el nombre de la agencia del huesped
CREATE OR REPLACE FUNCTION fn_agencia_huesped(p_id_huesped IN NUMBER)
RETURN VARCHAR2
IS
    v_agencia VARCHAR2(35);
BEGIN
    -- Obtenemos el nombre de la agencia usando JOIN
    SELECT a.nom_agencia INTO v_agencia
    FROM huesped h
    JOIN agencia a ON h.id_agencia = a.id_agencia
    WHERE h.id_huesped = p_id_huesped;
    
    RETURN v_agencia;
    
    
EXCEPTION
    WHEN OTHERS THEN
        DECLARE
            v_error VARCHAR2(300) := SQLERRM;
        BEGIN
            -- Registramos el error y devolvemos un mensaje
            INSERT INTO reg_errores (id_error, nomsubprograma, msg_error)
            
            VALUES (sq_error.NEXTVAL, 'fn_agencia_huesped', 
                    'id_huesped: ' || p_id_huesped || ' - ' || v_error);
            RETURN 'NO REGISTRA AGENCIA';
        END;
END;
/

-- Funcion que retorna el total de consumo en dinero de un huesped
CREATE OR REPLACE FUNCTION fn_consumos_huesped(p_id_huesped IN NUMBER)
RETURN NUMBER
IS
    v_total NUMBER := 0;
BEGIN
    SELECT monto_consumos INTO v_total
    FROM total_consumos
    WHERE id_huesped = p_id_huesped;
    
    RETURN NVL(v_total, 0);
    
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        -- Si no hay consumo devolvemos 0
        RETURN 0;
    WHEN OTHERS THEN
        DECLARE
            v_error VARCHAR2(300) := SQLERRM;
        BEGIN
        INSERT INTO reg_errores (id_error, nomsubprograma, msg_error)
        VALUES (sq_error.NEXTVAL, 'fn_consumos_huesped',
                'id_huesped: ' || p_id_huesped || ' - ' || v_error);
        RETURN 0;
        END;
END;
/

-- Package de hotel
CREATE OR REPLACE PACKAGE pkg_hotel AS
    -- Función que calcula el dinero total de tours del huesped
    FUNCTION fn_tours_huesped(p_id_huesped IN NUMBER) RETURN NUMBER;
END pkg_hotel;
/

-- Cuerpo del package
CREATE OR REPLACE PACKAGE BODY pkg_hotel AS

    -- Funcion mencionada
    FUNCTION fn_tours_huesped(p_id_huesped IN NUMBER) RETURN NUMBER
    IS
        v_total NUMBER := 0;
    BEGIN
        -- Sumar valor_tour * num_personas para todos los tours del huesped
        SELECT NVL(SUM(t.valor_tour * ht.num_personas), 0)
        INTO v_total
        FROM huesped_tour ht
        JOIN tour t ON ht.id_tour = t.id_tour
        WHERE ht.id_huesped = p_id_huesped;
        
        RETURN v_total;
        
    EXCEPTION
        WHEN OTHERS THEN
            RETURN 0;
    END fn_tours_huesped;

END pkg_hotel;
/

-- Procedimiento para el cobro de los huespedes
CREATE OR REPLACE PROCEDURE prc_cobro_huespedes(
    p_fecha       IN DATE,
    p_tipo_cambio IN NUMBER
)
IS
    -- Variables para calculos
    v_alojamiento       NUMBER;
    v_consumos          NUMBER;
    v_tours             NUMBER;
    v_valor_personas    NUMBER;
    v_subtotal          NUMBER;
    v_descuento_agencia NUMBER;
    v_descuento_consumos NUMBER;
    v_pct_consumos      NUMBER;
    v_total             NUMBER;
    v_nom_agencia       VARCHAR2(35);
    v_nombre_huesped    VARCHAR2(60);
    v_num_personas      NUMBER;
    
    -- Cursor que recorre huespedes que su fecha de salida coincida con p_fecha
    -- fecha salida = ingreso + estadia
    CURSOR cur_huespedes IS
        SELECT DISTINCT
            h.id_huesped,
            h.nom_huesped || ' ' || h.appat_huesped || ' ' || h.apmat_huesped AS nombre,
            r.id_reserva,
            r.ingreso,
            r.estadia
        FROM huesped h
        JOIN reserva r ON h.id_huesped = r.id_huesped
        WHERE r.ingreso + r.estadia = p_fecha;

BEGIN
    -- Limpiar tablas antes de reprocesar
    EXECUTE IMMEDIATE 'TRUNCATE TABLE detalle_diario_huespedes';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE reg_errores';
    
    FOR reg IN cur_huespedes LOOP
    
        -- Obtenemos el nombre de la agencia del huesped utilizando la funcion creada
        v_nom_agencia := fn_agencia_huesped(reg.id_huesped);
        
        -- Calculamos el valor de la estadia con (valor_habitacion + valor_minibar) * dias de estadia
        SELECT NVL(SUM((h.valor_habitacion + h.valor_minibar) * reg.estadia), 0)
        INTO v_alojamiento
        FROM detalle_reserva dr
        JOIN habitacion h ON dr.id_habitacion = h.id_habitacion
        WHERE dr.id_reserva = reg.id_reserva;
        
        -- Calculamos el total de consumo utilizando otra funcion creada
        v_consumos := fn_consumos_huesped(reg.id_huesped);
        
        -- Buscamos el porcentaje de descuento buscando el tramo en que caen los consumos
        -- Tambien protegemos en caso de que el tramo no exista para el valor v_consumos 
        BEGIN
            SELECT pct INTO v_pct_consumos
            FROM tramos_consumos
            WHERE v_consumos BETWEEN vmin_tramo AND vmax_tramo;
        EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    DECLARE
                    v_error VARCHAR2(300) := SQLERRM;
                    BEGIN
                        v_pct_consumos := 0;
                        INSERT INTO reg_errores (id_error, nomsubprograma, msg_error)
                        VALUES (sq_error.NEXTVAL, 'prc_cobro_huespedes',
                                'Sin tramo para consumo: ' || v_consumos || ' - huesped: ' || reg.id_huesped);
                    END;
                WHEN OTHERS THEN
                    DECLARE
                    v_error VARCHAR2(300) := SQLERRM;
                    BEGIN
                        v_pct_consumos := 0;
                        INSERT INTO reg_errores (id_error, nomsubprograma, msg_error)
                        VALUES (sq_error.NEXTVAL, 'prc_cobro_huespedes', v_error);
                    END;
        END;
        
        -- Calculamos el descuento
        v_descuento_consumos := ROUND(v_consumos * v_pct_consumos);
        
        -- Calculamos los tours utilizando el package del hotel, y su funcion integrada en el body
        v_tours := pkg_hotel.fn_tours_huesped(reg.id_huesped);
        
        -- Calculamos el valor por persona, se cobran 35.000 pesos por persona, que convertimos en dolares usando p_tipo_cambio
        SELECT NVL(SUM(ht.num_personas), 0) INTO v_num_personas
        FROM huesped_tour ht
        WHERE ht.id_huesped = reg.id_huesped;
        
        v_valor_personas := ROUND((35000 / p_tipo_cambio) * v_num_personas);
        
        -- Calculamos el subtotal
        v_subtotal := v_alojamiento + v_consumos + v_tours + v_valor_personas;
        
        -- Calculamos el posible descuento de la agencia, otorgamos un 12% solo si es 'Viajes Alberti'
        IF UPPER(v_nom_agencia) = 'VIAJES ALBERTI' THEN
            v_descuento_agencia := ROUND(v_subtotal * 0.12);
        ELSE
            v_descuento_agencia := 0;
        END IF;
        
        -- Calculamos el total, restandole al subtotal los posible descuentos
        v_total := v_subtotal - (v_descuento_consumos + v_descuento_agencia);
        
        -- Insertamos en DETALLE_DIARIO_HUESPEDES, tambien convertimos los valores a pesos y redondeamos
        INSERT INTO detalle_diario_huespedes VALUES (
            reg.id_huesped,
            INITCAP(reg.nombre),
            v_nom_agencia,
            ROUND(v_alojamiento    * p_tipo_cambio),
            ROUND(v_consumos       * p_tipo_cambio), 
            ROUND(v_tours          * p_tipo_cambio),
            ROUND(v_subtotal       * p_tipo_cambio), 
            ROUND(v_descuento_consumos * p_tipo_cambio),
            ROUND(v_descuento_agencia * p_tipo_cambio), -- descuento agencia en pesos
            ROUND(v_total          * p_tipo_cambio)   -- total en pesos
        );
    
    END LOOP;
    COMMIT;
    
EXCEPTION
    WHEN OTHERS THEN
        DECLARE
            v_error VARCHAR2(300) := SQLERRM;
        BEGIN
            ROLLBACK;
            INSERT INTO reg_errores (id_error, nomsubprograma, msg_error)
            VALUES (sq_error.NEXTVAL, 'prc_cobro_huespedes', v_error);
            COMMIT;
        END;
END;
/


EXEC prc_cobro_huespedes(TO_DATE('18/08/2021','DD/MM/YYYY'), 915);

SELECT * FROM detalle_diario_huespedes ORDER BY id_huesped;

SELECT * FROM reg_errores;
