import type { FastifyRequest } from "fastify";
import { describe, expect, it } from "vitest";
import { clientIp } from "../src/http.ts";

const from = (ip: string): FastifyRequest =>
  ({ headers: { "cf-connecting-ip": ip }, ip: "10.0.0.1" }) as unknown as FastifyRequest;

describe("clientIp", () => {
  it("keeps IPv4 and IPv4-mapped addresses whole", () => {
    expect(clientIp(from("203.0.113.7"))).toBe("203.0.113.7");
    expect(clientIp(from("::ffff:203.0.113.7"))).toBe("::ffff:203.0.113.7");
  });

  it("counts an IPv6 address as its /64, however it is written", () => {
    const network = "2001:db8:0:12::/64";
    expect(clientIp(from("2001:db8:0:12:1:2:3:4"))).toBe(network);
    expect(clientIp(from("2001:0db8:0000:0012:abcd::1"))).toBe(network);
    expect(clientIp(from("2001:db8:0:12::"))).toBe(network);
    expect(clientIp(from("2001:db8::"))).toBe("2001:db8:0:0::/64");
  });

  it("falls back to the socket address", () => {
    expect(clientIp({ headers: {}, ip: "10.0.0.1" } as unknown as FastifyRequest)).toBe("10.0.0.1");
  });
});
