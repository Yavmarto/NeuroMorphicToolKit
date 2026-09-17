"""NeuroML v2 XML exporter.

Converts a Nengo network into NeuroML v2 XML format for academic
interchange and publishing. Supports populations and connections.
"""

import xml.etree.ElementTree as ET
from xml.dom import minidom

import nengo


def export_neuroml(net: nengo.Network, *, indent: bool = True) -> str:
    """Export a Nengo network to NeuroML v2 XML.

    Parameters
    ----------
    net : nengo.Network
        A Nengo network with populations and connections.
    indent : bool
        If True, pretty-print the XML.

    Returns
    -------
    str
        NeuroML v2 XML string.
    """
    root = ET.Element("neuroml")
    root.set("xmlns", "http://www.neuroml.org/schema/neuroml2")
    root.set("id", net.label or "neurocnl_network")

    # Export neuron type (iafCell for LIF)
    cell_id = "lif_cell"
    iaf = ET.SubElement(root, "iafCell")
    iaf.set("id", cell_id)

    # Extract LIF params from first ensemble found
    for obj in net.all_ensembles:
        nt = obj.neuron_type
        if isinstance(nt, nengo.LIF):
            iaf.set("leakConductance", f"{1.0 / nt.tau_rc:.6f}nS")
            iaf.set("leakReversal", "0mV")
            iaf.set("thresh", "1mV")
            iaf.set("reset", "0mV")
            iaf.set("C", f"{nt.tau_rc:.6f}nF")
            iaf.set("refract", f"{nt.tau_ref:.6f}s")
            break

    # Export populations
    network_el = ET.SubElement(root, "network")
    network_el.set("id", net.label or "network")

    ensemble_ids = {}
    for i, ens in enumerate(net.all_ensembles):
        pop = ET.SubElement(network_el, "population")
        pop_id = ens.label or f"pop_{i}"
        pop_id = pop_id.replace(" ", "_").replace("-", "_")
        pop.set("id", pop_id)
        pop.set("component", cell_id)
        pop.set("size", str(ens.n_neurons))
        ensemble_ids[id(ens)] = pop_id

    # Export connections (projections)
    for i, conn in enumerate(net.all_connections):
        pre = conn.pre_obj
        post = conn.post_obj
        # Only export ensemble-to-ensemble connections
        pre_ens = pre if isinstance(pre, nengo.Ensemble) else getattr(pre, "ensemble", None)
        post_ens = post if isinstance(post, nengo.Ensemble) else getattr(post, "ensemble", None)

        if pre_ens and post_ens and id(pre_ens) in ensemble_ids and id(post_ens) in ensemble_ids:
            proj = ET.SubElement(network_el, "projection")
            proj_id = f"proj_{i}"
            if hasattr(conn, "label") and conn.label:
                proj_id = conn.label.replace(" ", "_").replace("-", "_")
            proj.set("id", proj_id)
            proj.set("presynapticPopulation", ensemble_ids[id(pre_ens)])
            proj.set("postsynapticPopulation", ensemble_ids[id(post_ens)])
            proj.set("synapse", "static_synapse")

            # Weight
            weight = 1.0
            if hasattr(conn, "transform"):
                t = conn.transform
                if hasattr(t, "init"):
                    w = t.init
                    if hasattr(w, "tolist"):
                        weight = float(w.flat[0]) if w.size > 0 else 1.0
                    elif isinstance(w, int | float):
                        weight = float(w)

            conn_el = ET.SubElement(proj, "connection")
            conn_el.set("id", "0")
            conn_el.set("preCellId", "../" + ensemble_ids[id(pre_ens)] + "[0]")
            conn_el.set("postCellId", "../" + ensemble_ids[id(post_ens)] + "[0]")
            conn_el.set("weight", str(weight))

    xml_str = ET.tostring(root, encoding="unicode")
    if indent:
        xml_str = minidom.parseString(xml_str).toprettyxml(indent="  ")
        # Remove extra XML declaration line
        lines = xml_str.split("\n")
        if lines and lines[0].startswith("<?xml"):
            xml_str = "\n".join(lines[1:])
    return xml_str.strip()
