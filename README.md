# SpaceRelay-Project
Framer-Physical Layer

## Overview  
The **Framer module** accepts an incoming payload and converts it into a continuous framed output as defined by the modem framing specification.

Key idea:
- **Payload is unpredictable (variable length)**  
- **Frame is predictable (fixed structure)**  
- The purpose of this module is to convert **variable-length input data** into a **continuous, deterministic framed output stream**.

Even if no payload is available, the framer will continue transmitting frames without gaps.

---

## Functional Description

- The framer constructs frames according to the document specification.
- Payload can be of any length.
- Output is always continuous; there are no idle cycles on the frame output.
- If payload is unavailable, the module generates an **IDLE payload** to maintain continuous framing using PRBS.
- Variable-length payload is mapped into a predictable frame structure.

---

## Design Assumptions

### 1. Header Construction  
  - `TXFN` is implemented using **2 bytes**.
  - `Frame_type` is implemented as **2 bit**
  - Some fields are populated (e.g., TXFN, Frame_type).
  - Remaining unused header bytes are filled with **zeros**.
- `TXFN` and `Frame_type` are provided as inputs to the module and appended into the header.
- **IDLE Payload Construction** requires an initial seed equal to the lower **15 bits of TXFN**.  
  Therefore, `TXFN` must be provided as an input to the module.

---

### 2. Data Width  
- `DATAWIDTH` is kept generic.
- It is assumed that `DATAWIDTH` is always an **integral multiple of 8 bits (byte-aligned)**.

---

### 3. Field Widths  
As per the datasheet:
- `payload_len` = 16 bits  
- `TXFN` = 16 bits  
- `Frame_type` = 2 bits  

These are **not hardcoded values** and follow the specification.

---

### 4. PL_Rate Handling  
- A default `PL_Rate` is selected in the switch-case.
- Any valid `PL_Rate` can be provided to the module.
- The default case can be modified as needed.
- No PL_Rate is hardcoded in logic.

---

### 5. Preamble  
- Preamble is a **64-bit constant**.
- Since both width and value are fixed:
  - It is not parameterized.
  - It is not treated as a variable field.

---

### 6. Scrambling  
- Scrambling is **not implemented** in this design.

---

### 7. Payload Segmentation  
- Payload segmentation is assumed to be handled by **higher layers**.
- The framer or physical layer does **not** perform segmentation.

---

## Summary  
This framer:
- Converts unpredictable payload into predictable framed output  
- Maintains continuous output with no gaps  
- Implements partial header fields per specification  
- Supports variable payload length  
- Generates IDLE payload when required  
- Assumes segmentation is handled upstream  

