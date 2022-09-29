FROM ocaml/opam:alpine

RUN opam install dune

WORKDIR /archetype

COPY . .

RUN sudo chown -R opam:nogroup . && \
    eval $(opam env) && \
    opam install . --deps-only --working-dir -y && \
    make
